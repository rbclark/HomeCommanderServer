require 'socket'
require 'pry'
require 'time_difference'
require 'serialport'

class Clients
  def initialize(server, device)
    @clients = []
    @server = server
    @lastUpdateTime = Time.now
    @state = Array.new(10, 0)
    @serialPort = SerialPort.new(device, 9600, 8, 1, SerialPort::NONE)
  end

  def addNewClients
    begin
      @clients << @server.accept_nonblock
      puts "Added client, total connections #{@clients.size}"
    rescue IO::WaitReadable, Errno::EINTR
    end
  end

  def recvAll
    @clients.each do |client|
      message = nil
      begin
        message = safelyRun(client) { |c| c.read_nonblock(10).delete("\0") }
      rescue IO::WaitReadable, Errno::EINTR
      end
      /\@PDS(?<deviceID>\d+)\?(?<state>\d+)\?/ =~ message
      unless (deviceID.nil? || deviceID.empty?)
        puts "Message received #{deviceID} #{state}"
        sendSerialMessage(deviceID, state)
        updateHDP
      end
    end
  end

  def sendSerialMessage(deviceID, state)
    @serialPort.write "@HAL#{state}?"
    @state[deviceID.to_i - 1] = state.to_i
  end

  def updateHDP
    @clients.each do |client|
      safelyRun(client) { |c| c.write "@HDP#{@state.join('')}?%" }
    end
    @lastUpdateTime = Time.now
  end

  def safelyRun(client)
    begin
      yield(client)
    rescue Errno::ECONNRESET, EOFError, Errno::EPIPE
      client.close
      @clients.delete(client)
      puts "Deleted client, total connections #{@clients.size}"
    end
  end

  def keepAliveAll
    if TimeDifference.between(Time.now, @lastUpdateTime).in_seconds > 4
      updateHDP
    end
  end

  def shutDown
    puts "Closing all clients and cleanly shutting down"
    @clients.each do |client|
      safelyRun(client) { |c| c.close }
    end
    puts "Done!"
  end
end

if ARGV[0].nil?
  puts "Usage: ./server.rb <TTYDevice> <optional server port>"
  exit
end

usbDevice = ARGV[0]
port = ARGV[1] || 80
server = TCPServer.new('0.0.0.0', port)
clients = Clients.new(server, usbDevice)

Signal.trap("INT") {
  clients.shutDown
  exit
}

# Trap `Kill `
Signal.trap("TERM") {
  clients.shutDown
  exit
}

puts "Listening for connections on port #{port}..."
loop do
  clients.addNewClients
  clients.keepAliveAll
  clients.recvAll
end
