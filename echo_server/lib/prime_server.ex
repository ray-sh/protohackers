defmodule PrimeServer do
  use GenServer
  require Logger
  @buff_limit 1024 * 100
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
      backlog: 100,
      packet: :line
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
          prime_handler(socket)
          :gen_tcp.close(socket)
        end)

        {:noreply, state, {:continue, :wait_connect}}

      {:error, reason} ->
        Logger.error(inspect(reason))
        {:stop, reason, state}
    end
  end

  defp prime_handler(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, packet} ->
        case Jason.decode(packet) do
          {:ok, %{"method" => "isPrime", "number" => num}} ->
            rsp = Jason.encode!(%{"method" => "isPrime", "isPrime" => prime?(num)})
            :gen_tcp.send(socket, [rsp, ?\n])

          _ ->
            :gen_tcp.send(socket, "malformed")
        end

        prime_handler(socket)

      other ->
        Logger.debug(inspect(other))
    end
  end

  defp prime?(number) when is_float(number), do: false
  defp prime?(number) when number <= 1, do: false
  defp prime?(number) when number in [2, 3], do: true

  defp prime?(number) do
    not Enum.any?(2..trunc(:math.sqrt(number)), &(rem(number, &1) == 0))
  end
end
