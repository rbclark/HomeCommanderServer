require 'socket'
require 'pry'
require 'time_difference'

class Clients
  def initialize
    @clients = []
    @lastUpdateTime = Time.now
    @state = Array.new(10, 0)
  end

  def recvAll
    @clients.each do |client|
      begin
        puts client.read_nonblock(10).delete("\0")
      rescue IO::WaitReadable, Errno::EINTR
      end
    end
  end

  def updateHDP
    @clients.each do |client|
      client.puts "@HDP#{@state.join('')}?%"
    end
  end

  def messageAll
    if TimeDifference.between(Time.now, @lastUpdateTime).in_seconds > 4
      @clients.each do |client|
        client.puts '@HAD0?10158?1?81.91?1012.66?79.50?0?%'
      end
      @lastUpdateTime = Time.now
    end
  end

  def <<(client)
    @clients << client
  end
end

server = TCPServer.new('0.0.0.0', 80)
clients = Clients.new
loop do
  begin
    clients << server.accept_nonblock
  rescue IO::WaitReadable, Errno::EINTR
  end

  clients.messageAll
  clients.recvAll
end
