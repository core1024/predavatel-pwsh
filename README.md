# About

This is an exercise Stremio add-on written in PowerShell.

I wrote it just for fun. It works as of the time it is written. This doesn't guarantee anything in future.

# Installation

Double click on `start_add-on.cmd` and wait for the manifest URL to be printed. Copy it and go to the Stremio's add-ons page. Then paste the URL in the filed labeled "Add-On Repository Url". You'll be asked for confirmation. Just press the install button and you're done.

# Usage

Now if you navigate to the Catalog/Channels, this add-on will be listed there and you can enjoy all the Bulgarian radio stations provided by `predavatel.com`.

# Internals

Upon startup the add-on navigates to the predavatel.com's web page and parses all the radio stations provided. This is a one-time operation as the sources does not change very often.

Then a HTTP server is spawn. It serves the pretty much static data acquired at startup according to [the Stremio's add-on protocol](https://github.com/Stremio/stremio-addon-sdk/tree/master/docs/ap://github.com/Stremio/stremio-addon-sdk/tree/master/docs/api).

# TODO:

 * Make this add-on works in Linux;
 * Handle search
 * Better media structure.
