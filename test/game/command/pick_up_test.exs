defmodule Game.Command.PickUpTest do
  use Data.ModelCase
  doctest Game.Command.PickUp

  @socket Test.Networking.Socket
  @room Test.Game.Room

  alias Data.Item
  alias Game.Command.PickUp

  setup do
    start_and_clear_items()
    item = create_item(%{name: "Short Sword", description: "A simple blade", keywords: ["sword"]})
    insert_item(item)

    @room.set_room(Map.merge(@room._room(), %{items: [Item.instantiate(item)]}))
    @socket.clear_messages()

    user = base_user()
    character = base_character(user)
    save = %{character.save | room_id: 1, items: [], currency: 1}
    %{state: session_state(%{user: user, character: character, save: save})}
  end

  test "pick up an item from a room", %{state: state} do
    @room.clear_pick_up()

    {:update, state} = PickUp.run({"sword"}, state)

    assert state.save.items |> length == 1

    [{_socket, look}] = @socket.get_echos()
    assert Regex.match?(~r(You picked up), look)
  end

  test "item does not exist in the room", %{state: state} do
    :ok = PickUp.run({"shield"}, state)

    [{_socket, look}] = @socket.get_echos()
    assert Regex.match?(~r("shield" could not be found), look)
  end

  test "item has already been removed", %{state: state} do
    @room.set_pick_up(:error)

    item = %Data.Item{id: 15, name: "shield"}
    room = %Data.Room{id: 1}
    assert {:error, :could_not_pickup, ^item} = PickUp.pick_up(item, room, state)
  end

  test "pick up gold from a room", %{state: state} do
    @room.set_pick_up_currency({:ok, 100})

    {:update, state} = PickUp.run({"gold"}, state)

    assert state.save.currency == 101

    [{_socket, look}] = @socket.get_echos()
    assert Regex.match?(~r(You picked up), look)
  end

  test "pick up gold from a room, but no gold", %{state: state} do
    @room.set_pick_up_currency({:error, :no_currency})

    :ok = PickUp.run({"gold"}, state)

    [{_socket, look}] = @socket.get_echos()
    assert Regex.match?(~r(There was no gold), look)
  end

  describe "pick up all" do
    test "gets everything", %{state: state} do
      @room.clear_pick_up()
      @room.set_pick_up_currency({:ok, 100})

      {:update, state} = PickUp.run({:all}, state)

      assert state.save.items |> length() == 1
      assert state.save.currency == 101

      [{_socket1, item}, {_socket2, currency}] = @socket.get_echos()
      assert Regex.match?(~r(You picked up), item)
      assert Regex.match?(~r(You picked up), currency)
    end

    test "does not echo currency if not available", %{state: state} do
      @room.clear_pick_up()
      @room.set_pick_up_currency({:error, :no_currency})

      {:update, state} = PickUp.run({:all}, state)

      assert state.save.items |> length() == 1
      assert state.save.currency == 1

      [{_socket1, item}] = @socket.get_echos()
      assert Regex.match?(~r(You picked up), item)
    end
  end
end
