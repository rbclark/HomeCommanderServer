# FMGames Home Commander Server

This server is able to communicate with the [FMGames Home Commander](https://play.google.com/store/apps/details?id=com.companyname.U_HomeCommander) application.

## Usage

    bundle install
    bundle exec ruby server.rb <TTYDevice> <optional server port>

The server will then startup on port 80 by default. If you wish to run on a different port you can pass it as the first argument the the program as shown above.
