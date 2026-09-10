#!/bin/bash
set -e
sudo cp -r PodcastResume /var/lib/squeezeboxserver/cache/InstalledPlugins/Plugins/
sudo systemctl restart lyrionmusicserver
echo "Deployed and restarted LMS"
