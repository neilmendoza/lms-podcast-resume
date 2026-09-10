# Podcast Resume for Lyrion Music Server

Automatically resumes podcast playback from where you last stopped.

## The problem

LMS's built-in Podcast plugin saves your playback position when you stop a podcast, but only resumes if you use the "Play from position" menu. If you just hit play on an episode you've already partially listened to, it starts from the beginning.

Additionally, podcasts saved to Favorites often bypass the Podcast plugin's protocol handler entirely, because the favorite is stored without the `parser` attribute needed to wrap URLs with the `podcast://` scheme.

## What this plugin does

1. **Auto-resume** -- Monkey-patches the Podcast ProtocolHandler's `getNextTrack` to check for a saved playback position and automatically seek to it when no explicit start time is set.

2. **Persistent positions** -- Saves playback positions to permanent storage (`Slim::Utils::Prefs`) on stop and pause, so they survive LMS restarts.

3. **Favorites fix** -- On startup, scans `favorites.opml` and adds `parser="Slim::Plugin::Podcast::Parser"` to any favorites that match feeds subscribed in the Podcast plugin but are missing the parser attribute.

## Installation

### Manual

Copy the `PodcastResume` directory to your LMS plugins directory:

```
cp -r PodcastResume /var/lib/squeezeboxserver/cache/InstalledPlugins/Plugins/
sudo systemctl restart lyrionmusicserver
```

### Via repository

Add the following repository URL in LMS Settings > Plugins:

```
https://raw.githubusercontent.com/neilmendoza/lms-podcast-resume/main/repo.xml
```

## Deployment

If developing from the git repo, use the included deploy script to copy the plugin and restart LMS:

```
./deploy.sh
```

The script assumes the default Debian/Ubuntu paths and service name (`lyrionmusicserver`). You may need to adjust the plugin directory and service name for your setup — common alternatives include `squeezeboxserver` and `logitechmediaserver`.

## Requirements

- Lyrion Music Server 7.6+
- The built-in Podcast plugin must be enabled

## Logging

Enable debug logging for `plugin.podcastresume` in Settings > Advanced > Logging to see resume activity.
