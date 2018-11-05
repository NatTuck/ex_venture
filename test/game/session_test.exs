defmodule Game.SessionTest do
  use GenServerCase
  use Data.ModelCase

  alias Data.Mail
  alias Game.Command
  alias Game.Message
  alias Game.Session
  alias Game.Session.Process

  @socket Test.Networking.Socket
  @room Test.Game.Room
  @zone Test.Game.Zone

  @basic_room %Game.Environment.State.Room{id: 1, name: "", description: "", players: [], shops: [], zone: %{id: 1, name: ""}}

  setup do
    @socket.clear_messages()
    @room.clear_notifies()

    user = base_user()
    character = base_character(user)

    state = session_state(%{
      session_started_at: Timex.now(),
      idle: Session.Help.init_idle(Timex.now()),
      user: user,
      character: character,
      save: character.save,
      skills: %{},
      regen: %{is_regenerating: false},
    })

    %{state: state}
  end

  test "echoing messages", %{state: state} do
    {:noreply, ^state} = Process.handle_cast({:echo, "a message"}, state)

    assert @socket.get_echos() == [{state.socket, "a message"}]
  end

  describe "regenerating" do
    setup %{state: state} do
      stats = %{
        health_points: 10,
        max_health_points: 15,
        skill_points: 9,
        max_skill_points: 12,
        endurance_points: 8,
        max_endurance_points: 10,

        intelligence: 20,
        vitality: 20,
      }

      state = Map.merge(state, %{
        save: %{
          room_id: 1,
          level: 2,
          stats: stats,
          experience_points: 10,
          config: %{
            regen_notifications: true,
          },
        },
        regen: %{
          is_regenerating: true,
          count: 5,
        },
      })

      %{state: state}
    end

    test "regens stats", %{state: state} do
      {:noreply, %{regen: %{count: 0}, save: %{stats: stats}}} = Process.handle_info(:regen, state)

      assert stats.health_points == 12
      assert stats.skill_points == 11
      assert stats.endurance_points == 9

      assert_received {:"$gen_cast", {:echo, ~s(You regenerated some health and skill points.)}}
    end

    test "does not echo if stats did not change", %{state: state} do
      stats = Map.merge(state.save.stats, %{
        health_points: 15,
        max_health_points: 15,
        skill_points: 12,
        max_skill_points: 12,
        endurance_points: 10,
        max_endurance_points: 10,
      })

      save = %{state.save | stats: stats}

      {:noreply, %{save: %{stats: stats}}} = Process.handle_info(:regen, %{state | save: save})

      assert stats.health_points == 15
      assert stats.skill_points == 12
      assert stats.endurance_points == 10

      refute_received {:"$gen_cast", {:echo, ~s(You regenerated some health and skill points.)}}
    end

    test "does not echo if config is off", %{state: state} do
      save = Map.merge(state.save, %{
        config: %{
          regen_notifications: false,
        },
      })

      {:noreply, %{save: %{stats: stats}}} = Process.handle_info(:regen, %{state | save: save})

      assert stats.health_points == 12
      assert stats.skill_points == 11
      assert stats.endurance_points == 9

      refute_receive {:"$gen_cast", {:echo, ~s(You regenerated some health and skill points.)}}
    end

    test "does not regen, only increments count if not high enough", %{state: state} do
      {:noreply, %{regen: %{count: 2}, save: %{stats: stats}}} =
        Process.handle_info(:regen, %{state | regen: %{is_regenerating: true, count: 1}})

      assert stats.health_points == 10
      assert stats.skill_points == 9
    end
  end

  test "recv'ing messages - the first", %{state: state} do
    {:noreply, state} = Process.handle_cast({:recv, "name"}, %{state | state: "login"})

    assert @socket.get_prompts() == []
    assert state.last_recv
  end

  test "recv'ing messages - after login processes commands", %{state: state} do
    user = create_user(%{name: "user", password: "password"})

    state = %{state | user: user, save: %{room_id: 1, experience_points: 10, stats: %{}}}
    {:noreply, state} = Process.handle_cast({:recv, "quit"}, state)

    assert @socket.get_echos() == [{state.socket, "Good bye."}]
    assert state.last_recv
  after
    Session.Registry.unregister()
  end

  test "processing a command that has continued commands", %{state: state} do
    user = create_user(%{name: "user", password: "password"})

    @room.set_room(%{@basic_room | exits: [%{direction: "north", start_id: 1, finish_id: 2}]})

    state = %{state | user: user,
      save: %{level: 1, room_id: 1, experience_points: 10, stats: %{base_stats() | endurance_points: 10}},
      regen: %{is_regenerating: false},
    }

    {:noreply, state} = Process.handle_cast({:recv, "run 2n"}, state)

    assert state.mode == "continuing"
    assert_receive {:continue, %Command{module: Command.Run, args: {["north"]}}}
  after
    Session.Registry.unregister()
  end

  test "continuing with processed commands", %{state: state} do
    user = create_user(%{name: "user", password: "password"})
    character = create_character(user)
    character = Repo.preload(character, [:race, class: [:skills]])

    @room.set_room(%{@basic_room | exits: [%{direction: "north", start_id: 1, finish_id: 2}]})

    state = %{state | character: character,
      save: %{level: 1, room_id: 1, experience_points: 10, stats: %{base_stats() | endurance_points: 10}},
      regen: %{is_regenerating: false},
    }

    command = %Command{module: Command.Run, args: {["north", "north"]}}
    {:noreply, _state} = Process.handle_info({:continue, command}, state)

    assert_receive {:continue, %Command{module: Command.Run, args: {["north"]}}}
  after
    Session.Registry.unregister()
  end

  test "does not process commands while mode is continuing", %{state: state} do
    state = %{state | mode: "continuing", save: %{room_id: 1}}
    {:noreply, state} = Process.handle_cast({:recv, "say Hello"}, state)

    assert state.mode == "continuing"
    assert @socket.get_echos() == []
  after
    Session.Registry.unregister()
  end

  test "user is not signed in yet does not save" do
    assert {:noreply, %{}} = Process.handle_info(:save, %{})
  end

  test "save the user's save", %{state: state} do
    user = create_user(%{name: "player", password: "password"})
    character = create_character(user, %{name: "player"})

    save = %{character.save | stats: %{character.save.stats | health_points: 10}}

    {:noreply, _state} = Process.handle_info(:save, %{state | user: user, character: character, save: save})

    character = Data.Character |> Data.Repo.get(character.id)
    assert character.save.stats.health_points == 10
  end

  test "checking for inactive players - not inactive", %{state: state} do
    {:noreply, _state} = Process.handle_info(:inactive_check, %{state | last_recv: Timex.now()})

    assert @socket.get_disconnects() == []
  end

  test "checking for inactive players - inactive", %{state: state} do
    state = %{state | is_afk: false, last_recv: Timex.now() |> Timex.shift(minutes: -66)}

    {:noreply, state} = Process.handle_info(:inactive_check, state)

    assert state.is_afk
  after
    Session.Registry.unregister()
  end

  describe "disconnects" do
    test "unregisters the pid when disconnected" do
      user = base_user()
      character = %{base_character(user) | seconds_online: 0}
      Session.Registry.register(character)

      state = session_state(%{user: user, character: character, session_started_at: Timex.now(), stats: %{}})
      {:stop, :normal, _state} = Process.handle_cast(:disconnect, state)
      assert Session.Registry.connected_players() == []
    after
      Session.Registry.unregister()
    end

    test "adds the time played" do
      user = create_user(%{name: "user", password: "password"})
      character = create_character(user, %{name: "player"})
      state = session_state(%{user: user, character: character, session_started_at: Timex.now() |> Timex.shift(hours: -3), stats: %{}})

      {:stop, :normal, _state} = Process.handle_cast(:disconnect, state)

      character = Repo.get(Data.Character, character.id)
      assert character.seconds_online == 10800
    end
  end

  test "applying effects", %{state: state} do
    effect = %{kind: "damage", type: "slashing", amount: 15}
    stats = %{base_stats() | health_points: 25, strength: 10}
    user = %{base_user() | id: 2, name: "user"}
    character = %{base_character(user) | class: class_attributes(%{})}
    save = %{base_save() | room_id: 1, experience_points: 10, stats: stats}

    state = %{state | user: user, character: character, save: save, is_targeting: MapSet.new}
    {:noreply, state} = Process.handle_cast({:apply_effects, [effect], {:npc, %{id: 1, name: "Bandit"}}, "description"}, state)
    assert state.save.stats.health_points == 15

    assert_received {:"$gen_cast", {:echo, ~s(description\n10 slashing damage is dealt) <> _}}
  end

  test "applying effects with continuous effects", %{state: state} do
    effect = %{kind: "damage/over-time", type: "slashing", every: 10, count: 3, amount: 15}

    stats = %{base_stats() | health_points: 25, strength: 10}
    save = %{base_save() | room_id: 1, experience_points: 10, stats: stats}
    user = %{base_user() | id: 2, name: "user"}
    character = %{base_character(user) | id: 2, class: class_attributes(%{}), save: save}
    state = %{state | user: user, character: character, save: save, is_targeting: MapSet.new()}

    from = {:npc, %{id: 1, name: "Bandit"}}

    {:noreply, state} = Process.handle_cast({:apply_effects, [effect], from, "description"}, state)

    assert state.save.stats.health_points == 15
    assert_received {:"$gen_cast", {:echo, ~s(description\n10 slashing damage is dealt) <> _}}

    [{^from, effect}] = state.continuous_effects
    assert effect.kind == "damage/over-time"
    assert effect.id

    effect_id = effect.id
    assert_receive {:continuous_effect, ^effect_id}
  end

  test "applying effects - died", %{state: state} do
    Session.Registry.register(base_character(base_user()))

    effect = %{kind: "damage", type: "slashing", amount: 15}
    stats = %{base_stats() | health_points: 5, strength: 10}
    user = %{base_user() | id: 2, name: "user"}
    character = base_character(user)
    save = %{base_save() | room_id: 1, experience_points: 10, stats: stats}

    state = %{state | user: user, character: character, save: save}
    {:noreply, state} = Process.handle_cast({:apply_effects, [effect], {:npc, %{id: 1, name: "Bandit"}}, "description"}, state)
    assert state.save.stats.health_points == -5

    assert_received {:"$gen_cast", {:echo, ~s(description\n10 slashing damage is dealt) <> _}}
    assert [{1, {"character/died", _, _, _}}] = @room.get_notifies()
  after
    Session.Registry.unregister()
  end

  test "applying effects - died with zone graveyard", %{state: state} do
    Session.Registry.register(base_character(base_user()))

    @room.set_room(@room._room())
    @zone.set_zone(Map.put(@zone._zone(), :graveyard_id, 2))

    effect = %{kind: "damage", type: "slashing", amount: 15}
    stats = %{base_stats() | health_points: 5, strength: 10}
    user = %{base_user() | id: 2, name: "user"}
    character = base_character(user)
    save = %{base_save() | room_id: 1, experience_points: 10, stats: stats}

    state = %{state | user: user, character: character, save: save, is_targeting: MapSet.new()}
    {:noreply, state} = Process.handle_cast({:apply_effects, [effect], {:npc, %{id: 1, name: "Bandit"}}, "description"}, state)

    assert state.save.stats.health_points == -5

    assert_receive {:resurrect, 2}
  after
    Session.Registry.unregister()
  end

  test "applying effects - died with no zone graveyard", %{state: state} do
    Session.Registry.register(base_character(base_user()))

    @room.set_room(@room._room())
    @zone.set_zone(Map.put(@zone._zone(), :graveyard_id, nil))
    @zone.set_graveyard({:error, :no_graveyard})

    effect = %{kind: "damage", type: "slashing", amount: 15}
    stats = %{base_stats() | health_points: 5, strength: 10}
    user = %{base_user() | id: 2, name: "user"}
    character = %{base_character(user) | class: class_attributes(%{})}
    save = %{base_save() | room_id: 1, experience_points: 10, stats: stats}

    state = %{state | user: user, character: character, save: save, is_targeting: MapSet.new()}
    {:noreply, state} = Process.handle_cast({:apply_effects, [effect], {:npc, %{id: 1, name: "Bandit"}}, "description"}, state)

    assert state.save.stats.health_points == -5

    refute_receive {:"$gen_cast", {:teleport, _}}
  after
    Session.Registry.unregister()
  end

  describe "targeted" do
    test "being targeted tracks the targeter", %{state: state} do
      targeter = {:player, %{id: 10, name: "Player"}}

      {:noreply, state} = Process.handle_cast({:targeted, targeter}, %{state | target: nil, is_targeting: MapSet.new})

      assert state.is_targeting |> MapSet.size() == 1
      assert state.is_targeting |> MapSet.member?({:player, 10})
    end

    test "if your target is empty, set to the targeter", %{state: state} do
      targeter = {:player, %{id: 10, name: "Player"}}

      {:noreply, state} = Process.handle_cast({:targeted, targeter}, %{state | target: nil, is_targeting: MapSet.new})

      assert state.target == {:player, 10}
    end
  end

  describe "channels" do
    setup do
      @socket.clear_messages()

      %{from: %{id: 10, name: "Player"}}
    end

    test "receiving a tell", %{state: state, from: from} do
      message = Message.tell(from, "Howdy")

      {:noreply, state} = Process.handle_info({:channel, {:tell, {:player, from}, message}}, state)

      [{_socket, tell} | _] = @socket.get_echos()
      assert Regex.match?(~r/Howdy/, tell)
      assert state.reply_to == {:player, from}
    end

    test "receiving a join", %{state: state} do
      save = %{channels: ["newbie"]}
      state = %{state | user: %{save: save}, save: save}

      {:noreply, state} = Process.handle_info({:channel, {:joined, "global"}}, state)
      assert state.save.channels == ["global", "newbie"]
    end

    test "does not duplicate channels list", %{state: state} do
      save = %{channels: ["newbie"]}
      state = %{state | user: %{save: save}, save: save}

      {:noreply, state} = Process.handle_info({:channel, {:joined, "newbie"}}, state)
      assert state.save.channels == ["newbie"]
    end

    test "receiving a leave", %{state: state} do
      save = %{channels: ["global", "newbie"]}
      state = %{state | user: %{save: save}, save: save}

      {:noreply, state} = Process.handle_info({:channel, {:left, "global"}}, state)
      assert state.save.channels == ["newbie"]
    end
  end

  describe "teleport" do
    setup do
      user = create_user(%{name: "user", password: "password"})
      character =
        user
        |> create_character()
        |> Repo.preload([:race, :class])

      zone = create_zone()
      room = create_room(zone)

      %{character: character, room: room}
    end

    test "teleports the character", %{state: state, character: character, room: room} do
      {:noreply, state} = Process.handle_cast({:teleport, room.id}, %{state | character: character, save: character.save})
      assert state.save.room_id == room.id
    end
  end

  describe "resurrection" do
    setup do
      @room.clear_enters()
      @room.clear_leaves()
    end

    test "sets health_points to 1 if < 0", %{state: state} do
      save = %{stats: %{base_stats() | health_points: -1}, experience_points: 10, room_id: 2}
      state = %{state | save: save}

      {:noreply, state} = Process.handle_info({:resurrect, 2}, state)

      assert state.save.stats.health_points == 1
      assert state.character.save.stats.health_points == 1
    end

    test "leaves old room, enters new room", %{state: state} do
      save = %{stats: %{base_stats() | health_points: -1}, experience_points: 10, room_id: 1}
      state = %{state | save: save}

      {:noreply, _state} = Process.handle_info({:resurrect, 2}, state)

      [{1, {:player, _}, :death}] = @room.get_leaves()
      [{2, {:player, _}, :respawn}] = @room.get_enters()
    end

    test "does not touch health_points if > 0", %{state: state} do
      save = %{stats: %{health_points: 2}, experience_points: 10}
      state = %{state | save: save}

      {:noreply, state} = Process.handle_info({:resurrect, 2}, state)

      assert state.save.stats.health_points == 2
    end
  end

  describe "event notification" do
    test "player enters the room", %{state: state} do
      {:noreply, ^state} = Process.handle_cast({:notify, {"room/entered", {{:player, %{id: 1, name: "Player"}}, {:enter, "south"}}}}, state)
      [{_, "{player}Player{/player} enters from the {command}south{/command}."}] = @socket.get_echos()
    end

    test "npc enters the room", %{state: state} do
      {:noreply, ^state} = Process.handle_cast({:notify, {"room/entered", {{:npc, %{id: 1, name: "Bandit"}}, {:enter, "south"}}}}, state)
      [{_, "{npc}Bandit{/npc} enters from the {command}south{/command}."}] = @socket.get_echos()
    end

    test "player leaves the room", %{state: state} do
      {:noreply, ^state} = Process.handle_cast({:notify, {"room/leave", {{:player, %{id: 1, name: "Player"}}, {:leave, "north"}}}}, state)
      [{_, "{player}Player{/player} leaves heading {command}north{/command}."}] = @socket.get_echos()
    end

    test "npc leaves the room", %{state: state} do
      {:noreply, ^state} = Process.handle_cast({:notify, {"room/leave", {{:npc, %{id: 1, name: "Bandit"}}, {:leave, "north"}}}}, state)
      [{_, "{npc}Bandit{/npc} leaves heading {command}north{/command}."}] = @socket.get_echos()
    end

    test "player leaves the room and they were the target", %{state: state} do
      state = %{state | target: {:player, 1}}
      {:noreply, state} = Process.handle_cast({:notify, {"room/leave", {{:player, %{id: 1, name: "Player"}}, {:leave, "north"}}}}, state)
      assert is_nil(state.target)
    end

    test "npc leaves the room and they were the target", %{state: state} do
      state = %{state | target: {:npc, 1}}
      {:noreply, state} = Process.handle_cast({:notify, {"room/leave", {{:npc, %{id: 1, name: "Bandit"}}, {:leave, "north"}}}}, state)
      assert is_nil(state.target)
    end

    test "room heard", %{state: state} do
      message = Message.say(%{id: 1, name: "Player"}, %{message: "hi"})
      {:noreply, ^state} = Process.handle_cast({:notify, {"room/heard", message}}, state)

      [{_socket, echo}] = @socket.get_echos()
      assert Regex.match?(~r(Hi.), echo)
    end

    test "room overheard - echos if user is not in the list of characters", %{state: state} do
      {:noreply, ^state} = Process.handle_cast({:notify, {"room/overheard", [], "hi"}}, state)

      [{_socket, echo}] = @socket.get_echos()
      assert Regex.match?(~r(hi), echo)
    end

    test "room overheard - does not echo if user is in the list of characters", %{state: state} do
      {:noreply, ^state} = Process.handle_cast({:notify, {"room/overheard", [{:player, state.character}], "hi"}}, state)

      assert [] = @socket.get_echos()
    end

    test "new mail received", %{state: state} do
      mail = %Mail{id: 1, sender: %{id: 10, name: "Player"}}

      {:noreply, ^state} = Process.handle_cast({:notify, {"mail/new", mail}}, state)

      [{_socket, echo}] = @socket.get_echos()
      assert Regex.match?(~r(New mail)i, echo)
    end

    test "character died", %{state: state} do
      npc = {:npc, %{id: 1, name: "bandit"}}

      {:noreply, ^state} = Process.handle_cast({:notify, {"character/died", npc, :character, npc}}, state)

      [{_socket, echo}] = @socket.get_echos()
      assert Regex.match?(~r(has died), echo)
    end

    test "new item received", %{state: state} do
      start_and_clear_items()
      insert_item(%{id: 1, name: "Potion"})
      instance = item_instance(1)

      state = %{state | user: %{save: nil}, save: %{items: []}}

      {:noreply, state} = Process.handle_cast({:notify, {"item/receive", {:npc, %{name: "Guard"}}, instance}}, state)

      assert state.save.items == [instance]

      [{_socket, echo}] = @socket.get_echos()
      assert Regex.match?(~r(Potion)i, echo)
      assert Regex.match?(~r(Guard)i, echo)
    end

    test "new currency received", %{state: state} do
      state = %{state | user: %{save: nil}, save: %{currency: 10}}

      {:noreply, state} = Process.handle_cast({:notify, {"currency/receive", {:npc, %{name: "Guard"}}, 50}}, state)

      assert state.save.currency == 60

      [{_socket, echo}] = @socket.get_echos()
      assert Regex.match?(~r(50 gold)i, echo)
      assert Regex.match?(~r(Guard)i, echo)
    end
  end

  describe "character dying" do
    setup %{state: state} do
      target = {:player, %{id: 10, name: "Player"}}
      user = %{id: 10, name: "Player", class: class_attributes(%{}), save: base_save()}

      state = Map.merge(state, %{
        user: user,
        save: user.save,
        target: {:player, 10},
        is_targeting: MapSet.new(),
      })

      %{state: state, target: target}
    end

    test "clears your target", %{state: state, target: target} do
      {:noreply, state} = Process.handle_cast({:notify, {"character/died", target, :character, {:player, state.user}}}, state)

      assert is_nil(state.target)
    end

    test "npc - a died message is sent and experience is applied", %{state: state} do
      target = {:npc, %{id: 10, original_id: 1, name: "Bandit", level: 1, experience_points: 1200}}
      state = %{state | target: {:npc, 10}}

      {:noreply, state} = Process.handle_cast({:notify, {"character/died", target, :character, {:player, state.user}}}, state)

      assert is_nil(state.target)
      assert state.save.level == 2
    end
  end
end
