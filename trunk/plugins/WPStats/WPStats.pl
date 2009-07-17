# ===========================================================================
# A Movable Type plugin to connect your site to WPStats.
# Copyright 2005 Everitz Consulting <everitz.com>.
#
# This program is free software:  You may redistribute it and/or modify it
# it under the terms of the Artistic License version 2 as published by the
# Open Source Initiative.
#
# This program is distributed in the hope that it will be useful but does
# NOT INCLUDE ANY WARRANTY; Without even the implied warranty of FITNESS
# FOR A PARTICULAR PURPOSE.
#
# You should have received a copy of the Artistic License with this program.
# If not, see <http://www.opensource.org/licenses/artistic-license-2.0.php>.
# ===========================================================================
package MT::Plugin::WPStats;

use base qw(MT::Plugin);
use strict;

use MT;

# stats server
use constant STATS_XMLRPC_SERVER => 'http://wordpress.com/xmlrpc.php';

# stats version
use constant STATS_VERSION => '1';

my $plugin = MT::Plugin::WPStats->new({
	name                 => 'MT-WPStats',
	description          => "<MT_TRANS phrase=\"Connect your Movable Type site to WPStats.\">",
	author_name          => 'Everitz Consulting',
	author_link          => 'http://everitz.com/',
#	plugin_link          => 'http://everitz.com/mt/wpstats/index.php',
#	doc_link             => 'http://everitz.com/mt/wpstats/index.php#install',
#	l10n_class           => 'WPStats::L10N',
	version              => '0.1.1',
	blog_config_template => 'settings_blog.tmpl',
	#
	# callbacks - 3.3x
	#
	callbacks      => {
		'CMSPostSave.entry' => {
			code => \&wpstats_post,
			priority => 10,
		},
	},
	#
	# tags - 3.3x
	#
	template_tags => {
		'WPStats' => \&wpstats_slug
	},
});
MT->add_plugin($plugin);

# plugin initialization

sub init_app {
	my $plugin = shift;
	my ($app) = @_;
	return unless ($app->isa('MT::App::CMS'));
	$app->add_methods(
		wpstats_configure => sub { wpstats_configure($plugin, @_) },
		wpstats_connect => sub { wpstats_connect($plugin, @_) },
	);
}

sub init_registry {
	my $plugin = shift;
	$plugin->registry({
		callbacks => {
			'MT::App::CMS::cms_post_save.entry' => \&wpstats_post,
			'MT::App::CMS::cms_post_save.page'  => \&wpstats_post,
		},
		tags => {
			function => {
				'WPStats' => \&wpstats_slug
			},
		},
	});
}

sub instance { $plugin }

sub load_config {
	my $plugin = shift;
	my ($args, $scope) = @_;

	$plugin->SUPER::load_config(@_);

	my $app = MT->instance;
	if ($app->isa('MT::App')) {
		if ($scope =~ /blog:(\d+)/) {
			my $blog_id = $1;
			$args->{blog_id} = $blog_id;
		}
	}
}

# functions

sub wpstats_configure {
	my $plugin = shift;
	my $app = shift;
	my $blog_id = $app->param('blog_id');
	my $api_key = $plugin->get_config_value('wpstats_api_key', 'blog:'.$blog_id);
	my $wpstats_blog_id = $plugin->get_config_value('wpstats_blog_id', 'blog:'.$blog_id);
	my %param;
	$param{'api_key'} = $api_key;
	$param{'blog_id'} = $blog_id;
  $param{'mt4'} = $app->version_number >= 4 ? 1 : 0;
	$param{'wpstats_blog_id'} = $wpstats_blog_id;
	$app->{cfg}->AltTemplatePath(MT::Plugin::WPStats->instance->envelope.'/tmpl/');
	$app->build_page('wpstats.tmpl', \%param);
}

sub wpstats_connect {
	my $plugin = shift;
	my $app = shift;
	my $blog_id = $app->param('blog_id');
	my $api_key = $app->param('api_key');
	my %param;
	if ($api_key) {
		require MT::Blog;
		my $blog = MT::Blog->load($blog_id);
		if ($blog) {
			require MT::Util;
			my %option = (
				'name' => MT::Util::remove_html($blog->name),
				'description' => MT::Util::remove_html($blog->description),
				'siteurl' => $blog->site_url,
				'version' => STATS_VERSION
			);
			my $host = $blog->site_url;
			$host =~ s!^http://!!;
			$host =~ s!/.*$!!;
			$option{'host'} = $host;
			my $path = $blog->site_url;
			$path =~ s!^http://!!;
			$path =~ s!$host!!;
			$path =~ s!/$!!;
			$option{'path'} = $path || '/';
			require XMLRPC::Lite;
			my $client = XMLRPC::Lite
				->proxy( STATS_XMLRPC_SERVER )
				->call( 'wpStats.get_blog_id', $api_key, \%option )
				->result;
			if (defined ($client)) {
				$param{'wpstats_blog_id'} = $client->{'blog_id'};
				$plugin->set_config_value('wpstats_api_key', $api_key, 'blog:'.$blog_id);
				$plugin->set_config_value('wpstats_blog_id', $client->{'blog_id'}, 'blog:'.$blog_id);
			} else {
				$param{'error_failed'} = $!;
			}
			$param{'api_key'} = $api_key;
			$param{'blog_id'} = $blog_id;
		  $param{'mt4'} = $app->version_number >= 4 ? 1 : 0;
			$app->{cfg}->AltTemplatePath(MT::Plugin::WPStats->instance->envelope.'/tmpl/');
			$app->build_page('wpstats_done.tmpl', \%param);
		} else {
			$param{'error_no_blog_id'} = 1;
		  $param{'mt4'} = $app->version_number >= 4 ? 1 : 0;
			$app->{cfg}->AltTemplatePath(MT::Plugin::WPStats->instance->envelope.'/tmpl/');
			$app->build_page('wpstats.tmpl', \%param);
		}
	} else {
		$param{'error_no_api_key'} = 1;
	  $param{'mt4'} = $app->version_number >= 4 ? 1 : 0;
		$app->{cfg}->AltTemplatePath(MT::Plugin::WPStats->instance->envelope.'/tmpl/');
		$app->build_page('wpstats.tmpl', \%param);
	}
}

sub wpstats_post {
	my ($cb, $app, $obj, $original) = @_;
	my $mt_blog = $obj->blog_id;
	my $api_key = $cb->plugin->get_config_value('wpstats_api_key', 'blog:'.$mt_blog);
	my $blog_id = $cb->plugin->get_config_value('wpstats_blog_id', 'blog:'.$mt_blog);
	my $mt = MT->instance;
	if ($api_key && $blog_id) {
		require MT::Util;
		my %option = (
			'id' => $obj->id,
			'permalink' => $obj->permalink,
			'title' => MT::Util::remove_html($obj->title),
			'type' => $obj->class_type eq 'entry' ? 'post' : 'page',
		);
		require XMLRPC::Lite;
		my $client = XMLRPC::Lite
			->proxy( STATS_XMLRPC_SERVER )
			->call( 'wpStats.update_postinfo', $api_key, $blog_id, \%option )
			->result;
	}
}

# tags

sub wpstats_slug {
	my ($ctx, $args) = @_;
	my $mt_blog = $ctx->stash('blog_id');
	return '' unless ($mt_blog);

	my $blog_id = $plugin->get_config_value('wpstats_blog_id', 'blog:'.$mt_blog);
	return '' unless ($blog_id);

	my $entry = $ctx->stash('entry');
	my $entry_id = ($entry) ? $entry->id : 0;

	my $ret = <<HTML;
<script src="http://stats.wordpress.com/e-<?php echo gmdate('YW'); ?>.js" type="text/javascript"></script>
<script type="text/javascript">
st_go({blog:'$blog_id',v:'ext',post:'$entry_id'});
var load_cmc = function(){linktracker_init($blog_id,$entry_id,2);};
if ( typeof addLoadEvent != 'undefined' ) addLoadEvent(load_cmc);
else load_cmc();
</script>
HTML

	$ret;
}

1;