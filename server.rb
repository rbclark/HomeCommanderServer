require 'socket'
require 'pry'
require 'time_difference'
require 'serialport'

class HomeCommander
  def initialize(server, device)
    # Clients are devices connected to the server via TCP socket
    @clients = []
    @server = server
    @lastUpdateTime = Time.now
    # This needs to be the same length as the number of values in HHS returned
    # from the serial port
    @state = Array.new(10, 0)
    # There should be a device on your system plugged in which is receiving
    # messages in some manner from an ardiuno. This device will send messages
    # if specific triggers happen and will receive messages when users request
    # specific events.
    @serialPort = SerialPort.new(device, 115200, 8, 1, SerialPort::NONE)
    # Do not wait when reading from serial port, if theres no data then move on
    @serialPort.read_timeout = -1
    # Halloween specific, there are 3 zones, we need to make sure that when
    # zones are triggered they only trigger once and are then locked
    @zone_states = Array.new(3, 0)
    @zone_trigger = Halloween.new(self)
  end

  def addNewClients
    begin
      @clients << @server.accept_nonblock
      puts "Added client, total connections #{@clients.size}"
    rescue IO::WaitReadable, Errno::EINTR
    end
  end

  def recvAll
    # Handle any messages received from the serial device
    message = @serialPort.read
    handleMessage(message)
    # Check if clients have directly requested for any devices to triggered
    # and trigger the requested device
    @clients.each do |client|
      message = nil
      begin
        message = safelyRun(client) { |c| c.read_nonblock(10).delete("\0") }
      rescue IO::WaitReadable, Errno::EINTR
      end
      handleMessage(message)
    end
  end

  def handleMessage(message)
    # Parse the full message and break it into the message type
    # and message body
    /\@(?<messageType>\w{3})(?<messageBody>.+)/ =~ message
    case messageType
    when 'PDS'
      /(?<deviceID>\d+)\?(?<state>\d+)/ =~ messageBody
      puts "PDS message received #{deviceID} #{state}"
      sendSerialMessage(deviceID, state)
    when 'HHS'
      puts "HHS message received"
      /(?<deviceStates>\d+)/ =~ messageBody
      @state = deviceStates.chars.map(&:to_i)
      updateClientHDP
    when 'ZSA'
      /(?<zone>\d+)/ =~ messageBody
      puts "ZSA zone #{zone} triggered"
      # If the zone is already running then just ignore the trigger
      if @zone[zone.to_i - 1].eql? 0
        @zone[zone.to_i - 1] = 1
        # Call zone1, zone2, or zone3 methods in a new thread
        Thread.new { @zone_trigger.public_send("zone#{zone}") }
      end
    end
  end

  def sendSerialMessage(deviceID, state)
    # Update clients before the device is triggered in an attempt to avoid
    # double triggers
    @state[deviceID.to_i - 1] = state.to_i
    updateClientHDP
    @serialPort.write "@HAL#{state}?"
  end

  def updateClientHDP
    @clients.each do |client|
      safelyRun(client) { |c| c.write "@HDP#{@state.join('')}?%" }
    end
    @lastUpdateTime = Time.now
  end

  # Execute a command against a client and handle any errors the client
  # may throw. If we receive an error from the client it is most likely
  # due to the client disconnecting. Clients automatically reconnect
  # after 20 seconds anyway, so it doesn't hurt to clean up and remove
  # the client if it is having issues.
  def safelyRun(client)
    begin
      yield(client)
    rescue Errno::ECONNRESET, EOFError, Errno::EPIPE
      client.close
      @clients.delete(client)
      puts "Deleted client, total connections #{@clients.size}"
    end
  end

  def updateZoneState(zone, state)
    @zone_states[zone.to_i - 1] = state.to_i
  end

  def keepAliveAll
    if TimeDifference.between(Time.now, @lastUpdateTime).in_seconds > 4
      updateClientHDP
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

# This class is used as a wrapper to trigger the zones in a new
# thread. It hopefully keeps the home commander class above from
# getting too messy, since all it has to do is call this class
# in a new thread.
class Halloween
  def initialize(home_commander)
    @home_commander = home_commander
  end

  def zone1
    @home_commander.sendSerialMessage(1, 1) # Turn spooky on
    sleep(3)
    @home_commander.sendSerialMessage(1, 0) # Turn spooky off
    # Let home commander know that this zone has completed running
    @home_commander.updateZoneState(1, 0)
  end

  def zone2
    # Let home commander know that this zone has completed running
    @home_commander.updateZoneState(2, 0)
  end

  def zone3
    # Let home commander know that this zone has completed running
    @home_commander.updateZoneState(3, 0)
  end
end

if ARGV[0].nil?
  puts "Usage: ./server.rb <TTYDevice> <optional server port>"
  exit
end

usbDevice = ARGV[0]
port = ARGV[1] || 80
server = TCPServer.new('0.0.0.0', port)
clients = HomeCommander.new(server, usbDevice)

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
