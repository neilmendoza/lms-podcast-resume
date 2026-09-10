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
my $myPrefs = preferences('plugin.podcastresume');

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	$cache = Slim::Utils::Cache->new;
	$myPrefs->init({ positions => {} });

	require Slim::Plugin::Podcast::ProtocolHandler;
	require Slim::Plugin::Podcast::Plugin;

	my $origOnStop = \&Slim::Plugin::Podcast::ProtocolHandler::onStop;

	no warnings 'redefine';
	*Slim::Plugin::Podcast::ProtocolHandler::getNextTrack = \&_getNextTrack;
	*Slim::Plugin::Podcast::ProtocolHandler::onStop = sub {
		my ($self, $song) = @_;
		$origOnStop->($self, $song);
		_savePosition($song);
	};
	use warnings 'redefine';

	Slim::Control::Request::subscribe(\&_onPause, [['playlist'], ['pause']]);

	_fixFavorites();

	$log->warn("Podcast auto-resume active (with persistent storage)");
}

sub _savePosition {
	my ($song) = @_;

	my $elapsed = eval { $song->master->controller->playingSongElapsed };
	return unless defined $elapsed;

	my ($httpUrl) = eval { Slim::Plugin::Podcast::Plugin::unwrapUrl($song->currentTrack->url) };
	return unless $httpUrl;

	my $positions = $myPrefs->get('positions') || {};

	if ($elapsed > 15 && (!$song->duration || $elapsed < $song->duration - 15)) {
		$positions->{$httpUrl} = int($elapsed);
		main::INFOLOG && $log->info("Persisted position for $httpUrl: $elapsed");
	} else {
		delete $positions->{$httpUrl};
		main::INFOLOG && $log->info("Cleared position for $httpUrl");
	}

	if (keys %$positions > 200) {
		my @sorted = sort { $positions->{$a} <=> $positions->{$b} } keys %$positions;
		delete $positions->{$_} for splice(@sorted, 0, keys(%$positions) - 200);
	}

	$myPrefs->set('positions', $positions);
}

sub _onPause {
	my $request = shift;
	return unless $request->getParam('_newvalue');

	my $client = $request->client() || return;
	my $song = $client->controller()->playingSong() || return;

	my ($httpUrl) = eval { Slim::Plugin::Podcast::Plugin::unwrapUrl($song->currentTrack->url) };
	return unless $httpUrl;

	_savePosition($song);
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

		my $positions = $myPrefs->get('positions') || {};
		my $saved = $positions->{$httpUrl};
		$saved //= $cache->get("podcast-$httpUrl");

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
