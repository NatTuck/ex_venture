defmodule Game.QuestTest do
  use Data.ModelCase

  alias Data.QuestProgress
  alias Data.QuestStep
  alias Game.Quest

  describe "start a quest" do
    test "creates a new quest progress record" do
      guard = create_npc(%{is_quest_giver: true})
      quest = create_quest(guard, %{name: "Into the Dungeon"})

      user = create_user()
      character = create_character(user)

      assert :ok = Quest.start_quest(character, quest)

      assert Quest.progress_for(character, quest.id)
    end
  end

  describe "start tracking a quest" do
    test "marks the quest progress as tracking" do
      guard = create_npc(%{is_quest_giver: true})
      quest = create_quest(guard, %{name: "Into the Dungeon"})

      user = create_user()
      character = create_character(user)

      Quest.start_quest(character, quest)

      {:ok, _qp} = Quest.track_quest(character, quest.id)

      {:ok, progress} = Quest.progress_for(character, quest.id)
      assert progress.is_tracking
    end

    test "does nothing if the quest progress is not found" do
      guard = create_npc(%{is_quest_giver: true})
      quest1 = create_quest(guard, %{name: "Into the Dungeon"})
      quest2 = create_quest(guard, %{name: "Into the Dungeon Again"})

      user = create_user()
      character = create_character(user)

      Quest.start_quest(character, quest1)
      {:ok, _} = Quest.track_quest(character, quest1.id)

      {:error, :not_started} = Quest.track_quest(character, quest2.id)

      {:ok, progress} = Quest.progress_for(character, quest1.id)
      assert progress.is_tracking
    end
  end

  describe "current step progress" do
    test "item/collect - no progress on a step yet" do
      step = %QuestStep{type: "item/collect", item_id: 1}
      progress = %QuestProgress{progress: %{}}
      save = %{items: []}

      assert Quest.current_step_progress(step, progress, save) == 0
    end

    test "item/collect - progress started" do
      step = %QuestStep{id: 1, type: "item/collect", item_id: 1}
      progress = %QuestProgress{progress: %{}}
      save = %{items: [item_instance(1)]}

      assert Quest.current_step_progress(step, progress, save) == 1
    end

    test "item/give - no progress on a step yet" do
      step = %QuestStep{type: "item/give", item_id: 1}
      progress = %QuestProgress{progress: %{}}
      save = %{}

      assert Quest.current_step_progress(step, progress, save) == 0
    end

    test "item/give - progress started" do
      step = %QuestStep{id: 1, type: "item/give", item_id: 1}
      progress = %QuestProgress{progress: %{step.id => 3}}
      save = %{}

      assert Quest.current_step_progress(step, progress, save) == 3
    end

    test "item/have - no progress on a step yet" do
      step = %QuestStep{type: "item/have", item_id: 1}
      progress = %QuestProgress{progress: %{}}
      save = %{items: [], wearing: %{}, wielding: %{}}

      assert Quest.current_step_progress(step, progress, save) == 0
    end

    test "item/have - progress started" do
      step = %QuestStep{id: 1, type: "item/have", item_id: 1}
      progress = %QuestProgress{progress: %{}}
      save = %{items: [item_instance(1)], wearing: %{chest: item_instance(1)}, wielding: %{}}

      assert Quest.current_step_progress(step, progress, save) == 2
    end

    test "item/have - progress complete" do
      step = %QuestStep{id: 1, type: "item/have", item_id: 1, count: 2}
      progress = %QuestProgress{status: "complete", progress: %{}}
      save = %{items: [], wearing: %{chest: item_instance(1)}, wielding: %{}}

      assert Quest.current_step_progress(step, progress, save) == 2
    end

    test "npc/kill - no progress on a step yet" do
      step = %QuestStep{type: "npc/kill"}
      progress = %QuestProgress{progress: %{}}
      save = %{}

      assert Quest.current_step_progress(step, progress, save) == 0
    end

    test "npc/kill - progress started" do
      step = %QuestStep{id: 1, type: "npc/kill"}
      progress = %QuestProgress{progress: %{step.id => 3}}
      save = %{}

      assert Quest.current_step_progress(step, progress, save) == 3
    end

    test "room/explore - no progress on a step yet" do
      step = %QuestStep{type: "room/explore"}
      progress = %QuestProgress{progress: %{}}
      save = %{}

      assert Quest.current_step_progress(step, progress, save) == false
    end

    test "room/explore - progress started" do
      step = %QuestStep{id: 1, type: "room/explore"}
      progress = %QuestProgress{progress: %{step.id => %{explored: true}}}
      save = %{}

      assert Quest.current_step_progress(step, progress, save) == true
    end
  end

  describe "determine if a user has all progress required for a quest" do
    test "quest complete when all step requirements are met - npc" do
      step = %QuestStep{id: 1, type: "npc/kill", count: 2}
      quest = %Data.Quest{quest_steps: [step]}
      progress = %QuestProgress{progress: %{step.id => 2}, quest: quest}
      save = %{}

      assert Quest.requirements_complete?(progress, save)
    end

    test "quest complete when all step requirements are met - item" do
      step = %QuestStep{id: 1, type: "item/collect", count: 2, item_id: 2}
      quest = %Data.Quest{quest_steps: [step]}
      progress = %QuestProgress{progress: %{}, quest: quest}
      save = %{items: [item_instance(2), item_instance(2)]}

      assert Quest.requirements_complete?(progress, save)
    end

    test "quest complete when all step requirements are met - item/give" do
      step = %QuestStep{id: 1, type: "item/give", count: 2, item_id: 2}
      quest = %Data.Quest{quest_steps: [step]}
      progress = %QuestProgress{progress: %{step.id => 2}, quest: quest}
      save = %{}

      assert Quest.requirements_complete?(progress, save)
    end

    test "quest complete when all step requirements are met - room/explored" do
      step = %QuestStep{id: 1, type: "room/explore", room_id: 2}
      quest = %Data.Quest{quest_steps: [step]}
      progress = %QuestProgress{progress: %{step.id => %{explored: true}}, quest: quest}
      save = %{}

      assert Quest.requirements_complete?(progress, save)
    end
  end

  describe "complete a quest" do
    test "marks the quest progress as complete" do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})
      goblin = create_npc(%{name: "Goblin"})
      quest = create_quest(guard, %{name: "Into the Dungeon"})
      potion = create_item(%{name: "Potion"})

      npc_step = create_quest_step(quest, %{type: "npc/kill", count: 3, npc_id: goblin.id})
      create_quest_step(quest, %{type: "item/collect", count: 1, item_id: potion.id})

      user = create_user()
      character = create_character(user)
      items = [item_instance(potion.id), item_instance(potion.id), item_instance(potion), item_instance(3)]
      character = %{character | save: %{character.save | items: items}}
      create_quest_progress(character, quest, %{progress: %{npc_step.id => 3}})
      {:ok, progress} = Quest.progress_for(character, quest.id) # get preloads

      {:ok, save} = Quest.complete(progress, character.save)

      assert Data.Repo.get(QuestProgress, progress.id).status == "complete"
      assert save.items |> length() == 3
    end
  end

  describe "track progress - npc kill" do
    setup do
      user = create_user()
      character = create_character(user)
      goblin = create_npc(%{name: "Goblin"})
      %{character: character, goblin: goblin}
    end

    test "no current quest that matches", %{character: character, goblin: goblin} do
      assert :ok = Quest.track_progress(character, {:npc, goblin})
    end

    test "updates any quest progresses that match the user and the npc", %{character: character, goblin: goblin} do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})
      quest = create_quest(guard, %{name: "Into the Dungeon", experience: 200})
      npc_step = create_quest_step(quest, %{type: "npc/kill", count: 3, npc_id: goblin.id})
      quest_progress = create_quest_progress(character, quest)

      assert :ok = Quest.track_progress(character, {:npc, goblin})

      quest_progress = Data.Repo.get(QuestProgress, quest_progress.id)
      assert quest_progress.progress == %{npc_step.id => 1}
    end

    test "ignores steps if they do not match the npc being passed in", %{character: character, goblin: goblin} do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})
      quest = create_quest(guard, %{name: "Into the Dungeon", experience: 200})
      create_quest_step(quest, %{type: "npc/kill", count: 3, npc_id: goblin.id})
      quest_progress = create_quest_progress(character, quest)

      assert :ok = Quest.track_progress(character, {:npc, guard})

      quest_progress = Data.Repo.get(QuestProgress, quest_progress.id)
      assert quest_progress.progress == %{}
    end
  end

  describe "track progress - exploring a room" do
    setup do
      user = create_user()
      character = create_character(user)
      zone = create_zone()
      room = create_room(zone, %{name: "Goblin Hideout"})

      %{character: character, room: room}
    end

    test "no current quest that matches", %{character: character, room: room} do
      assert :ok = Quest.track_progress(character, {:room, room.id})
    end

    test "moving in the overworld", %{character: character} do
      assert :ok = Quest.track_progress(character, {:room, "overworld:1:1,1,"})
    end

    test "updates any quest progresses that match the character and the room", %{character: character, room: room} do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})
      quest = create_quest(guard, %{name: "Into the Dungeon", experience: 200})
      npc_step = create_quest_step(quest, %{type: "room/explore", room_id: room.id})
      quest_progress = create_quest_progress(character, quest)

      assert :ok = Quest.track_progress(character, {:room, room.id})

      quest_progress = Data.Repo.get(QuestProgress, quest_progress.id)
      assert quest_progress.progress == %{npc_step.id => %{explored: true}}
    end

    test "ignores steps if they do not match the room being passed in", %{character: character, room: room} do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})
      quest = create_quest(guard, %{name: "Into the Dungeon", experience: 200})
      create_quest_step(quest, %{type: "room/explore", room_id: room.id})
      quest_progress = create_quest_progress(character, quest)

      assert :ok = Quest.track_progress(character, {:room, -1})

      quest_progress = Data.Repo.get(QuestProgress, quest_progress.id)
      assert quest_progress.progress == %{}
    end
  end

  describe "track progress - give an item to an npc" do
    setup do
      user = create_user()
      character = create_character(user)
      baker = create_npc(%{name: "Baker"})
      flour = create_item(%{name: "Flour"})
      flour_instance = item_instance(flour.id)

      %{character: character, baker: baker, flour: flour_instance}
    end

    test "no current quest that matches", %{character: character, baker: baker, flour: flour} do
      assert :ok = Quest.track_progress(character, {:item, flour, baker})
    end

    test "updates any quest progresses that match the character, the npc, and the item", %{character: character, baker: baker, flour: flour} do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})
      quest = create_quest(guard, %{name: "Into the Dungeon", experience: 200})
      npc_step = create_quest_step(quest, %{type: "item/give", count: 3, item_id: flour.id, npc_id: baker.id})
      quest_progress = create_quest_progress(character, quest)

      assert :ok = Quest.track_progress(character, {:item, flour, baker})

      quest_progress = Data.Repo.get(QuestProgress, quest_progress.id)
      assert quest_progress.progress == %{npc_step.id => 1}
    end

    test "ignores steps if they do not match the npc being passed in", %{character: character, baker: baker, flour: flour} do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})
      quest = create_quest(guard, %{name: "Into the Dungeon", experience: 200})
      create_quest_step(quest, %{type: "item/give", count: 3, item_id: flour.id, npc_id: baker.id})
      quest_progress = create_quest_progress(character, quest)

      assert :ok = Quest.track_progress(character, {:item, flour, guard})

      quest_progress = Data.Repo.get(QuestProgress, quest_progress.id)
      assert quest_progress.progress == %{}
    end

    test "ignores steps if they do not match the item being passed in", %{character: character, baker: baker, flour: flour} do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})
      quest = create_quest(guard, %{name: "Into the Dungeon", experience: 200})
      create_quest_step(quest, %{type: "item/give", count: 3, item_id: flour.id, npc_id: baker.id})
      quest_progress = create_quest_progress(character, quest)

      assert :ok = Quest.track_progress(character, {:item, item_instance(0), baker})

      quest_progress = Data.Repo.get(QuestProgress, quest_progress.id)
      assert quest_progress.progress == %{}
    end
  end

  describe "next available quest" do
    test "find the next quest available from an NPC" do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})

      quest1 = create_quest(guard, %{name: "Root 1"})
      quest2 = create_quest(guard, %{name: "Root 2"})
      quest3 = create_quest(guard, %{name: "Child Root 1"})
      create_quest_relation(quest3, quest1)
      quest4 = create_quest(guard, %{name: "Child Root 2"})
      create_quest_relation(quest4, quest2)
      quest5 = create_quest(guard, %{name: "Child Child Root 1"})
      create_quest_relation(quest5, quest3)

      user = create_user()
      character = create_character(user)

      {:ok, next_quest} = Quest.next_available_quest_from(guard, character)
      assert next_quest.id == quest1.id

      create_quest_progress(character, quest1, %{status: "complete"})
      {:ok, next_quest} = Quest.next_available_quest_from(guard, character)
      assert next_quest.id == quest2.id

      create_quest_progress(character, quest2, %{status: "complete"})
      {:ok, next_quest} = Quest.next_available_quest_from(guard, character)
      assert next_quest.id == quest3.id

      create_quest_progress(character, quest3, %{status: "complete"})
      {:ok, next_quest} = Quest.next_available_quest_from(guard, character)
      assert next_quest.id == quest4.id

      create_quest_progress(character, quest4, %{status: "complete"})
      {:ok, next_quest} = Quest.next_available_quest_from(guard, character)
      assert next_quest.id == quest5.id

      create_quest_progress(character, quest5, %{status: "complete"})
      assert {:error, :no_quests} = Quest.next_available_quest_from(guard, character)
    end

    test "stops if a parent quest is not complete" do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})

      quest1 = create_quest(guard, %{name: "Root 1"})
      quest2 = create_quest(guard, %{name: "Root 2"})
      quest3 = create_quest(guard, %{name: "Child Root 1"})
      create_quest_relation(quest3, quest1)
      create_quest_relation(quest3, quest2)

      user = create_user()
      character = create_character(user)

      {:ok, next_quest} = Quest.next_available_quest_from(guard, character)
      assert next_quest.id == quest1.id

      create_quest_progress(character, quest1, %{status: "complete"})
      {:ok, next_quest} = Quest.next_available_quest_from(guard, character)
      assert next_quest.id == quest2.id

      create_quest_progress(character, quest2, %{status: "active"})
      assert {:error, :no_quests} = Quest.next_available_quest_from(guard, character)
    end

    test "can find a quest that is in the middle of a quest chain" do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})
      captain = create_npc(%{name: "Captain", is_quest_giver: true})

      quest1 = create_quest(guard, %{name: "Root 1"})
      quest2 = create_quest(guard, %{name: "Root 2"})
      quest3 = create_quest(captain, %{name: "Child Root 1"})
      create_quest_relation(quest3, quest1)

      user = create_user()
      character = create_character(user)

      create_quest_progress(character, quest1, %{status: "complete"})
      create_quest_progress(character, quest2, %{status: "complete"})

      {:error, :no_quests} = Quest.next_available_quest_from(guard, character)

      {:ok, next_quest} = Quest.next_available_quest_from(captain, character)
      assert next_quest.id == quest3.id
    end

    test "does not give out a quest if you are below its level" do
      guard = create_npc(%{name: "Guard", is_quest_giver: true})

      create_quest(guard, %{level: 2})

      user = create_user()
      character = create_character(user)

      {:error, :no_quests} = Quest.next_available_quest_from(guard, character)
    end
  end
end
