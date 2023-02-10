defmodule ChatServer do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl GenServer
  def init(_) do
    listen_options = [
      ifaddr: {0, 0, 0, 0},
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false,
      backlog: 100,
      packet: :line
    ]

    case :gen_tcp.listen(5002, listen_options) do
      {:ok, socket} ->
        Logger.info("chat server listend on 5002")
        {:ok, %{lsocket: socket}, {:continue, :wait_con}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_continue(:wait_con, state) do
    Registry.start_link(
      keys: :duplicate,
      name: MessageBroker,
      partitions: System.schedulers_online()
    )

    case :gen_tcp.accept(state.lsocket) do
      {:ok, socket} ->
        Logger.info("client connected #{inspect(socket)}")
        Logger.info("start chat handler")
        {:ok, handler} = GenServer.start_link(ChatHandler, socket)
        :gen_tcp.controlling_process(socket, handler)
        {:noreply, state, {:continue, :wait_con}}

      {:error, reason} ->
        Logger.error("accept error #{inspect(reason)}")
        {:stop, reason}
    end
  end
end

defmodule ChatHandler do
  use GenServer
  require Logger
  defstruct [:name, :socket]
  @impl true
  def init(socket) do
    {:ok, %__MODULE__{socket: socket}, {:continue, :reg_name}}
  end

  defp valid_name?(name) do
    Logger.info("Reg name: #{name}")
    # at least 1 char and only alphanumeric characters
    if String.length(name) < 1 or String.length(name) > 16 or
         !Regex.match?(~r/^[a-zA-Z0-9]+$/, name) do
      false
    else
      true
    end
  end

  @impl true
  def handle_continue(:reg_name, state) do
    :gen_tcp.send(state.socket, "Welcome to budgetchat! What shall I call you?\n")

    case :gen_tcp.recv(state.socket, 0) do
      {:ok, name} ->
        name = String.trim(name)

        cond do
          valid_name?(name) ->
            # Broad_cast_new_user come, and reg new_user event
            Registry.dispatch(MessageBroker, "chat", fn entries ->
              for {pid, _} <- entries,
                  do: send(pid, {:broadcast, "* #{name} has entered the room\n"})
            end)

            # send existing user to client
            users =
              Registry.select(MessageBroker, [{{:"$1", :"$2", :"$3"}, [], [:"$3"]}])
              |> Enum.join(", ")

            :gen_tcp.send(state.socket, "* The room contains: #{users}\n")
            # duplicated name is allowed
            Registry.register(MessageBroker, "chat", name)

            :inet.setopts(state.socket, active: true)

          true ->
            :gen_tcp.send(state.socket, "illegal name, name length should between 1~16 chars")
            :gen_tcp.close(state.socket)
        end

        {:noreply, %{state | name: name}}

      {:error, reason} ->
        Logger.error(inspect(reason))
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:broadcast, msg}, state) do
    :gen_tcp.send(state.socket, msg)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("client disconnect")
    Registry.unregister(MessageBroker, "chat")

    Registry.dispatch(MessageBroker, "chat", fn entries ->
      for {pid, _} <- entries,
          do: send(pid, {:broadcast, "* user #{state.name} leave the room\n"})
    end)

    {:stop, :normal, state}
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("breaker receive #{inspect(msg)}")

    case msg do
      {:tcp, _, msg} ->
        msg = String.trim(msg)
        Logger.info("user #{state.name} say #{msg} to everyone")

        Registry.dispatch(MessageBroker, "chat", fn entries ->
          IO.inspect(entries)

          for {pid, name} <- entries,
              name != state.name,
              do: send(pid, {:broadcast, "* [#{state.name}] #{msg}\n"})
        end)

      _ ->
        Logger.warn(:unknow_message)
    end

    {:noreply, state}
  end
end
