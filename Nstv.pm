package Nstv;
our $VERSION = '0.2.1';

use 5.10.0;
use strict;
use warnings;
use Carp;
use YAML::Syck qw/LoadFile/;
use Encode qw/encode decode decode_utf8/;
use Time::Piece ();

sub new {
    my $class = shift;
    my $self = bless {
        conf => {},
        uri => '',
        tsv => '',
        tmp => '',
        @_ ,
    }, $class;
    return $self;
}

sub boot {
    my $self = shift;
    my ($config, $tsvdir) = @_;
    $self->load_config($config);
    $self->setup_filenames($tsvdir);
    $self->is_exist_tsv;
    $self->get_html;
    $self->output_tsv;
}

sub load_config {
    my $self = shift;
    my ($config) = @_;
    $self->log("config: $config");
    eval { $self->{conf} = LoadFile($config); };
    croak "$config: $!" if ($@);
}

sub setup_filenames {
    my $self = shift;
    my ($dir) = @_;

    # Get Today
    my $t = Time::Piece::localtime();
    my $ymdu = sprintf '%04d_%02d_%02d', $t->year, $t->mon, $t->mday;
    my $ymd = $ymdu;
    $ymd =~ s/_//g;

    # TSV spool dir.
    mkdir $dir if not -d $dir;

    # URI and Filenames.
    $self->{uri} = $self->{conf}->{uri};
    $self->{uri} =~ s/YYYYMMDD/$ymd/;
    $self->{tsv} = "$dir/nstv_$ymdu.tsv";
    $self->{cache} = "$dir/nstv_cache.html";
}

sub is_exist_tsv {
    my $self = shift;
    if (-f $self->{tsv}) {
        my $siz = -s $self->{tsv};
        if ($siz > 0) {
            $self->log("isexist $self->{tsv}: $siz bytes.");
            return 1;
        }
    }
    return 0;
}

sub get_html {
    my $self = shift;
    if (-f $self->{cache} and
        time - _timestamp($self->{cache}) < $self->{conf}->{expire_cache}) {
        $self->log("Using cache html: $self->{cache}");
        return;
    }
    $self->log("GET $self->{uri}");
    _httpget($self->{uri}, $self->{cache});
}

sub output_tsv {
    my $self = shift;
    my $tsv = $self->{tsv};
    my $tmptsv = "$tsv.$$";
    my $html = _get_content($self->{cache});
    my $text = $self->html_to_tsv(\$html);      # Parse html
    open my $out, '>', $tmptsv or croak $!;
    print $out $text;
    close $out;
    if (-f $tsv) {
        if (-s $tmptsv > -s $tsv) {
            $self->log("Overwrite: $tsv");
            unlink $tsv;
            rename $tmptsv, $tsv;
        }
        else {
            $self->log("Thru: $tsv");
            unlink $tmptsv;
        }
    }
    else {
        $self->log("Output: $tsv");
        rename $tmptsv, $tsv;
    }
}

# HTML encoding is euc-jp.
sub html_to_tsv {
    my $self = shift;
    my ($html_ref) = @_;
    my $html = $$html_ref;
    my $rv = '';

    # Delete all newline and split the columns.
    $html =~ s/[\r\n]//g;       
    $html =~ s/<TD /\n<TD /g;

    # Parse!
    foreach my $line (split /\n/, $html) {
        next if ($line !~ /^<TD class=/);
        if ($line =~ m|>(\d+):(\d\d).*(/DET[^"]+)">(.+?)</a>(.*?)</TD>|) {
            my ($hh, $mm, $link, $name, $desc) = ($1, $2, $3, $4, $5);
            $link = 'http://tv.infoseek.co.jp' . $link;
            my $sta = $self->get_station_name($link);
            my $hm = sprintf '%02d:%02d', $hh, $mm;
            my $iepg = '-';
            if ($line =~ m|<a href="(/tvpi\.epg[^"]+)"|) {
                $iepg = "http://tv.infoseek.co.jp$1";
            }
            _remove_tag(\$name);
            _remove_tag(\$desc);
            $desc = '-' if (!$desc);
            $rv .= join "\t", ($hm, $sta, $name, $desc, $link, $iepg);
            $rv .= "\n";
        }
    }

    # Error
    if ($rv eq '') {
        my $err = "Parse error when make a tsv from html file. abort.";
        $self->log($err);
        croak $err;
    }

    return $rv;
}

sub get_station_name {
    my $self = shift;
    my ($link) = @_;
    my $name;
    if ($link =~ /program=p(\d\d\d\d)/) {
        my $sid = $1;
        $name = encode($self->{conf}->{tsv_encoding},
                      decode('utf8', $self->{conf}->{stations}{$sid}));
        $name = $sid if not $name;
    }
    return $name;
}

sub log {
    my($self, $msg) = @_;
    my $ymd= localtime;
    chomp($msg);
    if ($self->{conf}->{log_encoding}) {
        $msg = Encode::decode_utf8($msg) unless utf8::is_utf8($msg);
        $msg = Encode::encode($self->{conf}->{log_encoding}, $msg);
    }
    warn "$ymd [$$] $msg\n";
}

sub _remove_tag {
    my($html_ref) = @_;
    $$html_ref =~ s|<img src=.+? alt="(.+?)".*?>|\[$1\]|g;
    $$html_ref =~ s|\[[^\]]+?iEPG[^\]]+?\]||g;
    $$html_ref =~ s|<.*?>||g;
    $$html_ref = '-' if (not $$html_ref);
}

sub _httpget {
    my ($uri, $file) = @_;
    use LWP::UserAgent;
    open my $wfh, '>', $file or croak "$file:$!";
    binmode $wfh;
    my $res = LWP::UserAgent->new->get($uri,
        ':content_cb' => sub {
            my ($chunk, $res, $proto) = @_;
            print $wfh $chunk;
        });
    close $wfh;
    croak "$res->status_line" if ($res->status_line !~ /^200/);
}

sub _get_content {
    my ($file) = @_;
    open my $in, '<', $file or croak "$file: $!";
    my $content = do { local $/; <$in> };
    close $in;
    return $content;
}

sub _timestamp {
    my ($filename) = @_;
    my ($mydev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,
        $blksize,$blocks) = stat($filename) or carp $!;
    return $mtime || 0;
}

1;
