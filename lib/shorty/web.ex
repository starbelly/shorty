defmodule Shorty.Web do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def stop(server) do
    GenServer.call(server, :stop)
  end

  def init(_) do
    {:ok, [], {:continue, :setup}}
  end

  def handle_continue(:setup, _state) do
    # Option Notes: 
    #   - binary: we want our packets in binaries
    #   - active: we want to handle send/recv of packets ourselves
    #   - packet: We expect http packages and would like the erlang packet encode/decoder
    #             to handle wrapping/unwrapping for us

    opts = [
      :binary,
      {:active, false},
      {:packet, :http_bin}
    ]

    {:ok, socket} = :gen_tcp.listen(4000, opts)

    # A pool or a pond...  a pond is good for this example. 
    # We will create as many acceptors as we have schedulers... a lagom number of acceptors. 
    num_acceptors = :erlang.system_info(:schedulers)

    # Note the the simpler scheduler option... if we were to decide to increase the number of
    # acceptors, say * 2, we'd have to assign every two processes per scheduler

    spawn_acceptors = fn i ->
      name = String.to_atom("acceptor_number_#{i}")
      pid = :erlang.spawn_opt(__MODULE__, :accept, [socket, i], [:link, {:scheduler, i}])

      Process.register(
        pid,
        name
      )
    end

    Enum.each(1..num_acceptors, spawn_acceptors)
    {:noreply, %{socket: socket}}
  end

  def accept(listen_socket, id) do
    # TODO: Error handling and supervison. We should have workers and a supervisor dedicated to listening.

    {:ok, socket} = :gen_tcp.accept(listen_socket)
    Process.spawn(__MODULE__, :read, [socket, %Shorty.Conn{}], [{:scheduler, id}])

    # Block and wait again
    accept(listen_socket, id)
  end

  def read(socket, %Shorty.Conn{} = conn) do
    # TODO: Error handling and supervision. This could be spun up in a transient process 
    # under a seperate supervisor and it should be. 

    # The 0 argument denotes we will read in whatever the client has sent regardless of size.
    # We also impose no timeout during the operation. It should be noted both 0 and a timeout 
    # option are only available when active mode is false. 

    # Right now we're just spitting out a form that does nothing... we should
    # use a callback provided via config and make use of eex. We also naievely assume everything
    # will go right and so we hardcode a status of 200 in for the moment. 

    # TODO: conn work - We need to scoop up the rest of the headers, parse params, etc.  

    case :gen_tcp.recv(socket, 0) do
      {:ok, :http_eoh} ->
        :gen_tcp.send(socket, header_and_content(200, form_string()))
        :gen_tcp.close(socket)
        IO.inspect(conn)

      {:ok, {:http_request, method, {:abs_path, path}, {1, 1}}} ->
        read(socket, %{conn | method: method, path: path})

      {:ok, _data} ->
        read(socket, conn)
    end
  end

  def header_and_content(status, content) do
    size = byte_size(content)
    "HTTP/1.1 #{status} OK\r\nContent-Length: #{size}\r\n\r\n#{content}"
  end

  def form_string do
    """
    <!DOCTYPE html>
    <html>
      <body>
        <h2>Shorty</h2>
         <form action="/" method="post">
           <input type="text" name="url" value="" placeholder="url">
           <br><br>
           <input type="submit" value="Submit">
        </form> 
      </body>
    </html>
    """
  end
end
