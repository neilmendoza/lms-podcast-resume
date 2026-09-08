package Plugins::PodcastResume::Plugin;

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Cache;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.podcastresume',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_PODCAST_RESUME',
});

my $cache;

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	$cache = Slim::Utils::Cache->new;

	require Slim::Plugin::Podcast::ProtocolHandler;
	require Slim::Plugin::Podcast::Plugin;

	no warnings 'redefine';
	*Slim::Plugin::Podcast::ProtocolHandler::getNextTrack = \&_getNextTrack;
	use warnings 'redefine';

	_fixFavorites();

	$log->warn("Podcast auto-resume active");
}

sub _getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	my $seekdata = $song->seekdata;

	if ($seekdata && (my $startTime = $seekdata->{startTime})) {
		$song->seekdata($song->getSeekData($startTime));
		main::INFOLOG && $log->info("starting from $startTime");
	}
	else {
		my ($httpUrl) = Slim::Plugin::Podcast::Plugin::unwrapUrl($song->currentTrack->url);
		my $saved = $cache->get("podcast-$httpUrl");
		main::INFOLOG && $log->info("auto-resume: $httpUrl saved=" . (defined $saved ? $saved : 'none'));

		if ($saved && $saved > 15) {
			$song->seekdata($song->getSeekData($saved));
			main::INFOLOG && $log->info("auto-resuming from $saved");
		}
	}

	$successCb->();
}

sub _fixFavorites {
	my $podcastPrefs = preferences('plugin.podcast');
	my $feeds = $podcastPrefs->get('feeds') || [];
	my %podcastUrls = map { $_->{value} => 1 } @$feeds;

	return unless %podcastUrls;

	my $prefsDir = preferences('server')->get('prefsdir');
	my $favFile = "$prefsDir/favorites.opml";

	return unless -f $favFile;

	open(my $fh, '<:utf8', $favFile) or do {
		$log->warn("Cannot read $favFile: $!");
		return;
	};
	my $content = do { local $/; <$fh> };
	close $fh;

	my $fixed = 0;
	$content =~ s{(<outline\b[^>]*\btype="link"[^>]*?)(\s*/>)}{
		my ($attrs, $close) = ($1, $2);
		my ($url) = $attrs =~ /\bURL="([^"]+)"/;
		if ($url && $podcastUrls{$url} && $attrs !~ /\bparser=/) {
			$fixed++;
			qq{$attrs parser="Slim::Plugin::Podcast::Parser"$close};
		} else {
			"$attrs$close";
		}
	}ge;

	if ($fixed) {
		open(my $wfh, '>:utf8', $favFile) or do {
			$log->warn("Cannot write $favFile: $!");
			return;
		};
		print $wfh $content;
		close $wfh;
		$log->warn("Added Podcast parser to $fixed favorites entries");
	}
}

sub getDisplayName { return 'PLUGIN_PODCAST_RESUME' }

1;
