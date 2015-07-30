#!/usr/local/bin/perl
use warnings;
use strict;
use Data::Dumper;
use Log::Message::Simple;
use Time::Seconds;
use Time::Piece;

my $verbose = (defined $ARGV[0] && $ARGV[0] eq "-v") ? 1 : 0;

my %zfsobjs;
foreach (`/sbin/zfs get -Hp name,type,used,creation`) {
    chomp;
    my @f = split('[\t]');
    $zfsobjs{$f[0]}{$f[1]} = $f[2];
}

my @snapshots = grep {
    $zfsobjs{$_}{type} eq "snapshot"
#    && $zfsobjs{$_}{name} =~ /pool\/dataset/
} keys %zfsobjs;

# find the latest snapshot for each dataset
# with descending iteration
my %latest_snapshot;
foreach ( sort { $zfsobjs{$b}{creation} <=> $zfsobjs{$a}{creation} }
    @snapshots) {

    my @f = split('@');
    my $dataset = $f[0];
    if (!defined $latest_snapshot{$dataset}) {
        $latest_snapshot{$dataset} = $_;
    }

}

my $today = Time::Piece->strptime(localtime->strftime("%Y-%m-%d"), "%Y-%m-%d");

# filter snapshots by comparing to adjacent snapshots
# with ascending iteration
my @snapshots_to_destroy;
my %prev_snapshot;
foreach ( sort { $zfsobjs{$a}{creation} <=> $zfsobjs{$b}{creation} }
    @snapshots) {

    my @f = split('@');
    my $dataset = $f[0];
    my $creation = localtime($zfsobjs{$_}{creation});
    my $prev_snapshot_creation;

    if (defined $prev_snapshot{$dataset}) {
        $prev_snapshot_creation = localtime($zfsobjs{$prev_snapshot{$dataset}}{creation});
    } else {
        $prev_snapshot_creation = localtime(0);
    }
    my $elapsed = $today - $creation;
    my $elapsed_prev_snapshot = $creation - $prev_snapshot_creation;

    debug("", $verbose);
    debug("snapshot:   $_", $verbose);
    debug("used space: " . $zfsobjs{$_}{used}, $verbose);
    debug("taken:      " . sprintf("%.1f", $elapsed->days) . " days ago", $verbose);
    debug("last taken: " . sprintf("%.1f", $elapsed_prev_snapshot->days) . " days ago", $verbose);

    # keep the latest snapshot
    if ($_ eq $latest_snapshot{$dataset}) {
        debug("KEEP latest", $verbose);
        next;
    }

    # for non-empty snapshots
    if ($zfsobjs{$_}{used} != 0) {
        # keep all for 2 weeks
        if ($elapsed->days <= 14) {
            $prev_snapshot{$dataset} = $_;
            next;
        }
        # per day for 2 months
        elsif ($elapsed->months <= 2 && $elapsed_prev_snapshot->days >= 1) {
            $prev_snapshot{$dataset} = $_;
            next;
        }
        # per week for 1 year
        elsif ($elapsed->years <= 1 && $elapsed_prev_snapshot->weeks >= 1) {
            $prev_snapshot{$dataset} = $_;
            next;
        }
        # per month for 5 years
        elsif ($elapsed->years <= 5 && $elapsed_prev_snapshot->months >= 1) {
            $prev_snapshot{$dataset} = $_;
            next;
        }
    }

    # remove all other snapshots
    debug("REMOVE", $verbose);
    push @snapshots_to_destroy, $_;
}

msg("# list of snapshots to be destoryed:", $verbose);
foreach (`/sbin/zfs list -o name,used,creation -s creation @snapshots_to_destroy`) {
    chomp;
    msg($_, $verbose);
}

msg("# finally, comes the commands:", $verbose);
foreach (@snapshots_to_destroy) {
    print "/sbin/zfs destroy $_\n";
}
