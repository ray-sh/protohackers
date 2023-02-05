defmodule EchoServer do
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
    Logger.info("waiting client #{state.n_client} ...")

    case :gen_tcp.accept(state.lsocket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(MyTask, fn ->
          with {:ok, msg} <- read_msg(socket, "", 0) do
            Logger.info("send received msg back")
            :gen_tcp.send(socket, msg)
          else
            error ->
              Logger.error(inspect(error))
          end

          Logger.info("close socket for client #{state.n_client}")
          :gen_tcp.close(socket)
        end)

        {:noreply, %{state | n_client: state.n_client + 1}, {:continue, :wait_connect}}

      {:error, reason} ->
        Logger.error(inspect(reason))
        {:stop, reason, state}
    end
  end

  defp read_msg(socket, bs, bs_size) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, packet} when bs_size + byte_size(packet) > @buff_limit ->
        {:error, :out_of_buffer_limit}

      {:ok, packet} ->
        # Logger.debug(
        #   "recevie #{byte_size(packet)} byte, buffer size is #{bs_size + byte_size(packet)}"
        # )

        read_msg(socket, [bs, packet], bs_size + byte_size(packet))

      {:error, :closed} ->
        Logger.info("Recieved byte size #{bs_size}")
        {:ok, bs}
    end
  end
end
