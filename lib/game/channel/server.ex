defmodule Game.Channel.Server do
  @moduledoc """
  Server implementation details
  """

  require Logger

  alias Data.ChannelMessage
  alias Data.Repo
  alias Game.Channel
  alias Game.Channels
  alias Metrics.CommunicationInstrumenter
  alias Web.Endpoint

  @doc """
  Get a list of channels the pid is subscribed to
  """
  @spec subscribed_channels(Channel.state(), pid()) :: [String.t()]
  def subscribed_channels(state, pid)

  def subscribed_channels(%{channels: channels}, pid) do
    channels
    |> Enum.filter(fn {_channel, pids} -> Enum.member?(pids, pid) end)
    |> Enum.map(fn {channel, _pids} ->
      Channels.get(channel)
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Join a channel

  Adds the pid to the channel's list of pids for broadcasting to. Will also send
  back to the process that the join was successful.
  """
  @spec join_channel(Channel.state(), String.t(), pid()) :: Channel.state()
  def join_channel(state = %{channels: channels}, channel, pid) do
    Process.link(pid)
    channel_pids = Map.get(channels, channel, [])
    channels = Map.put(channels, channel, [pid | channel_pids])
    send(pid, {:channel, {:joined, channel}})
    Map.put(state, :channels, channels)
  end

  @doc """
  Leave a channel

  Removes the pid from the channel's list of pids. Will also send back to the process
  after the leave was successful.
  """
  @spec leave_channel(Channel.state(), String.t(), pid()) :: Channel.state()
  def leave_channel(state = %{channels: channels}, channel, pid) do
    channel_pids =
      channels
      |> Map.get(channel, [])
      |> Enum.reject(&(&1 == pid))

    channels = Map.put(channels, channel, channel_pids)
    send(pid, {:channel, {:left, channel}})
    Map.put(state, :channels, channels)
  end

  @doc """
  Broadcast a message to a channel
  """
  @spec broadcast(Channel.state(), String.t(), Message.t(), Keyword.t()) :: :ok
  def broadcast(state, channel, message, opts \\ [])

  def broadcast(state, channel, message, []) do
    Logger.info("Channel '#{channel}' message: #{inspect(message.formatted)}", type: :channel)
    CommunicationInstrumenter.channel_broadcast(channel)

    Endpoint.broadcast("chat:#{channel}", "broadcast", %{message: message.formatted})

    channel
    |> Channels.get()
    |> maybe_record_message(message)
    |> maybe_send_to_gossip(message)

    Channel.pg2_key()
    |> :pg2.get_members()
    |> Enum.reject(&(&1 == self()))
    |> Enum.each(fn member ->
      GenServer.cast(member, {:broadcast, channel, message, [echo: true]})
    end)

    local_broadcast(state, channel, message)
  end

  def broadcast(state, channel, message, echo: true) do
    local_broadcast(state, channel, message)
  end

  defp maybe_record_message(channel, message) do
    case channel.is_gossip_connected do
      true ->
        channel

      false ->
        params = %{
          channel_id: channel.id,
          character_id: message.sender.id,
          message: message.message,
          formatted: message.formatted
        }

        %ChannelMessage{}
        |> ChannelMessage.changeset(params)
        |> Repo.insert()

        channel
    end
  end

  defp maybe_send_to_gossip(channel, message) do
    case channel.is_gossip_connected do
      true ->
        case message.from_gossip do
          true ->
            channel

          false ->
            send_to_gossip(channel, message)

            channel
        end

      false ->
        channel
    end
  end

  defp send_to_gossip(channel, message) do
    message = %{
      name: message.sender.name,
      message: message.message,
    }

    Gossip.broadcast(channel.gossip_channel, message)
  end

  defp local_broadcast(%{channels: channels}, channel, message) do
    channels
    |> Map.get(channel, [])
    |> Enum.each(fn pid ->
      send(pid, {:channel, {:broadcast, channel, message}})
    end)
  end

  @doc """
  Send a tell to a player

  A message will be sent to the player's session in the form of `{:channel, {:tell, from, message}}`.
  """
  @spec tell(Channel.state(), Character.t(), Character.t(), Message.t()) :: :ok
  def tell(%{tells: tells}, {type, who}, from, message) do
    case tells |> Map.get("tells:#{type}:#{who.id}", nil) do
      nil ->
        nil

      pid ->
        send(pid, {:channel, {:tell, from, message}})
    end
  end

  @doc """
  The session process died, due to a crash or the player quitting.

  Leave all channels and their player tell channel.
  """
  @spec process_died(Channel.state(), pid()) :: Channel.state()
  def process_died(state = %{channels: channels, tells: tells}, pid) do
    channels =
      Enum.reduce(channels, %{}, fn {channel, pids}, channels ->
        pids = pids |> Enum.reject(&(&1 == pid))
        Map.put(channels, channel, pids)
      end)

    tells =
      tells
      |> Enum.reject(fn {_, tell_pid} -> tell_pid == pid end)
      |> Enum.into(%{})

    state
    |> Map.put(:channels, channels)
    |> Map.put(:tells, tells)
  end
end
