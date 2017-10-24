# FMGames Home Commander Server

This server is able to communicate with the [FMGames Home Commander](https://play.google.com/store/apps/details?id=com.companyname.U_HomeCommander) application.

## Usage

    bundle install
    sudo -E bundle exec ruby server.rb

sudo is required since it binds to port 80. This is a limitation of the Home Commander application.
