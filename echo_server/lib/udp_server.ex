defmodule UdpServer do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl true
  def init(_) do
    listen_options = [
      mode: :binary,
      active: false
    ]

    case :gen_udp.open(5002, listen_options) do
      {:ok, socket} ->
        {:ok, %{socket: socket, db: %{"version" => "Protohackers in Elixir 1.0"}},
         {:continue, :wait_req}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:wait_req, state) do
    case :gen_udp.recv(state.socket, 0) do
      {:ok, {ip, port, data}} ->
        Logger.info("receive #{data}")

        state =
          case String.split(data, "=", parts: 2) do
            ["version", _value] ->
              state

            [key, val] ->
              %{state | db: Map.put(state.db, key, val)}

            [key] ->
              :gen_udp.send(state.socket, ip, port, "#{key}=#{Map.get(state.db, key)}")
              state
          end

        {:noreply, state, {:continue, :wait_req}}

      {:error, reason} ->
        Logger.error("Error when recv data #{inspect(reason)}")
        {:stop, reason}
    end
  end
end
