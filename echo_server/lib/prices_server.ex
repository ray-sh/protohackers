defmodule PricesServer do
  alias Hacker.PricesDb
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, "")
  end

  @impl GenServer
  def init(_args) do
    Task.Supervisor.start_link(name: MyTask, max_children: 100)

    listen_options = [
      ifaddr: {0, 0, 0, 0},
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false,
      backlog: 100
    ]

    case :gen_tcp.listen(5002, listen_options) do
      {:ok, lsocket} ->
        {:ok, %{lsocket: lsocket, n_client: 0}, {:continue, :wait_connect}}

      {:error, error} ->
        Logger.error("can't listen on the port #{inspect(error)}")
        {:stop, error}
    end
  end

  @impl GenServer
  def handle_continue(:wait_connect, state) do
    Logger.info("waiting client ...")

    case :gen_tcp.accept(state.lsocket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(MyTask, fn ->
          handle_requests(socket, PricesDb.new())

          :gen_tcp.close(socket)
        end)

        {:noreply, state, {:continue, :wait_connect}}

      {:error, reason} ->
        Logger.error(inspect(reason))
        {:stop, reason, state}
    end
  end

  defp handle_requests(socket, db) do
    case :gen_tcp.recv(socket, 9) do
      {:ok, packet} ->
        case packet do
          <<?I, ts::32, price::32>> ->
            handle_requests(socket, PricesDb.add(db, ts, price)) |> dbg()

          <<?Q, from::32, to::32>> ->
            result = PricesDb.query(db, from, to)
            {:ok, result}
            Logger.info("avg is #{result}")
            :gen_tcp.send(socket, <<result::32>>)

          _ ->
            :error
        end

      {:error, :timeout} ->
        handle_requests(socket, db)

      other ->
        Logger.debug(inspect(other))
        :error
    end
  end
end
