package Mojo::URL;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Mojo::Parameters;
use Mojo::Path;
use Mojo::Util qw/punycode_decode punycode_encode url_escape url_unescape/;

has [qw/fragment host port scheme userinfo/];
has base => sub { Mojo::URL->new };

# Characters (RFC 3986)
our $UNRESERVED = 'A-Za-z0-9\-\.\_\~';
our $SUBDELIM   = '!\$\&\'\(\)\*\+\,\;\=';
our $PCHAR      = "$UNRESERVED$SUBDELIM\%\:\@";

# IPv4 regex (RFC 3986)
my $DEC_OCTET_RE = qr/(?:[0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])/;
our $IPV4_RE =
  qr/^$DEC_OCTET_RE\.$DEC_OCTET_RE\.$DEC_OCTET_RE\.$DEC_OCTET_RE$/;

# IPv6 regex (RFC 3986)
my $H16_RE  = qr/[0-9A-Fa-f]{1,4}/;
my $LS32_RE = qr/(?:$H16_RE:$H16_RE|$IPV4_RE)/;
our $IPV6_RE = qr/(?:
                                           (?: $H16_RE : ){6} $LS32_RE
  |                                     :: (?: $H16_RE : ){5} $LS32_RE
  | (?:                      $H16_RE )? :: (?: $H16_RE : ){4} $LS32_RE
  | (?: (?: $H16_RE : ){0,1} $H16_RE )? :: (?: $H16_RE : ){3} $LS32_RE
  | (?: (?: $H16_RE : ){0,2} $H16_RE )? :: (?: $H16_RE : ){2} $LS32_RE
  | (?: (?: $H16_RE : ){0,3} $H16_RE )? ::     $H16_RE :      $LS32_RE
  | (?: (?: $H16_RE : ){0,4} $H16_RE )? ::                    $LS32_RE
  | (?: (?: $H16_RE : ){0,5} $H16_RE )? ::                    $H16_RE
  | (?: (?: $H16_RE : ){0,6} $H16_RE )? ::
)/x;

sub new {
  my $self = shift->SUPER::new();
  $self->parse(@_);
  return $self;
}

sub authority {
  my ($self, $authority) = @_;

  # Set
  if (defined $authority) {
    my $userinfo = '';
    my $host     = $authority;

    # Userinfo
    if ($authority =~ /^([^\@]+)\@(.+)$/) {
      $userinfo = $1;
      $host     = $2;
      url_unescape $userinfo;
      $self->userinfo($userinfo);
    }

    # Port
    my $port = undef;
    if ($host =~ /^(.+)\:(\d+)$/) {
      $host = $1;
      $self->port($2);
    }

    # Host
    url_unescape $host;
    return $host =~ /[^\x00-\x7f]/
      ? $self->ihost($host)
      : $self->host($host);
  }

  # *( unreserved / pct-encoded / sub-delims ), extended with "[" and "]"
  # to support IPv6
  my $host = $self->ihost;
  my $port = $self->port;

  # *( unreserved / pct-encoded / sub-delims / ":" )
  my $userinfo = $self->userinfo;
  url_escape $userinfo, "$UNRESERVED$SUBDELIM\:" if $userinfo;

  # Format
  $authority .= "$userinfo\@" if $userinfo;
  $authority .= lc($host || '');
  $authority .= ":$port" if $port;

  return $authority;
}

sub clone {
  my $self = shift;

  my $clone = Mojo::URL->new;
  $clone->scheme($self->scheme);
  $clone->authority($self->authority);
  $clone->path($self->path->clone);
  $clone->query($self->query->clone);
  $clone->fragment($self->fragment);
  $clone->base($self->base->clone) if $self->{base};

  return $clone;
}

sub ihost {
  my ($self, $host) = @_;

  # Set
  if (defined $host) {

    # Decode parts
    my @decoded;
    for my $part (split /\./, $_[1]) {
      if ($part =~ /^xn--(.+)$/) {
        $part = $1;
        punycode_decode $part;
      }
      push @decoded, $part;
    }
    $self->host(join '.', @decoded);

    return $self;
  }

  # Host
  return unless $host = $self->host;
  return $host unless $host =~ /[^\x00-\x7f]/;

  # Encode parts
  my @encoded;
  for my $part (split /\./, $host || '') {
    if ($part =~ /[^\x00-\x7f]/) {
      punycode_encode $part;
      $part = "xn--$part";
    }
    push @encoded, $part;
  }

  return join '.', @encoded;
}

sub is_abs {
  my $self = shift;
  return 1 if $self->scheme && $self->authority;
  return;
}

sub is_ipv4 {
  return 1 if shift->host =~ $IPV4_RE;
  return;
}

sub is_ipv6 {
  return 1 if shift->host =~ $IPV6_RE;
  return;
}

sub parse {
  my ($self, $url) = @_;
  return $self unless $url;

  # Official regex
  my ($scheme, $authority, $path, $query, $fragment) = $url
    =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;
  $self->scheme($scheme);
  $self->authority($authority);
  $self->path->parse($path);
  $self->query->parse($query);
  $self->fragment($fragment);

  return $self;
}

sub path {
  my ($self, $path) = @_;

  # Set
  if ($path) {

    # Plain path
    if (!ref $path) {

      # Absolute path
      if ($path =~ /^\//) { $path = Mojo::Path->new($path) }

      # Relative path
      else {
        my $new = Mojo::Path->new($path);
        $path = $self->{path} || Mojo::Path->new;
        pop @{$path->parts} unless $path->trailing_slash;
        push @{$path->parts}, @{$new->parts};
        $path->leading_slash(1);
        $path->trailing_slash($new->trailing_slash);
      }
    }
    $self->{path} = $path;

    return $self;
  }

  # Get
  $self->{path} ||= Mojo::Path->new;
  return $self->{path};
}

sub query {
  my $self = shift;

  # Set
  if (@_) {

    # Replace with list
    if (@_ > 1) {
      $self->{query} = Mojo::Parameters->new(ref $_[0] ? @{$_[0]} : @_);
    }

    # Merge with array
    elsif (ref $_[0] && ref $_[0] eq 'ARRAY') {
      my $q = $self->{query} ||= Mojo::Parameters->new;
      my $merge = Mojo::Parameters->new(@{$_[0]});
      for my $name ($merge->param) {
        $q->param($name => $merge->param($name));
      }
    }

    # Append hash
    elsif (ref $_[0] && ref $_[0] eq 'HASH') {
      my $q = $self->{query} ||= Mojo::Parameters->new;
      $q->append(%{$_[0]});
    }

    # Replace with string or object
    else {
      $self->{query} =
        !ref $_[0] ? Mojo::Parameters->new->append($_[0]) : $_[0];
    }

    return $self;
  }

  # Get
  $self->{query} ||= Mojo::Parameters->new;
  return $self->{query};
}

sub to_abs {
  my $self = shift;
  my $base = shift || $self->base->clone;

  # Absolute URL
  my $abs = $self->clone;
  return $abs if $abs->is_abs;

  # Add scheme and authority
  $abs->scheme($base->scheme);
  $abs->authority($base->authority);

  # New base
  $abs->base($base->clone);
  my $new = $base->path->clone;

  # Replace path
  my $old = $self->path;
  if ($old->leading_slash) { $new->parts([@{$old->parts}]) }

  # Merge paths
  else {

    # Characters after the right-most '/' need to go
    pop @{$new->parts} unless $new->trailing_slash;

    $new->append($_) for @{$old->parts};
  }

  # Update
  $new->leading_slash(1);
  $new->trailing_slash($old->trailing_slash);
  $abs->path($new);

  return $abs;
}

sub to_rel {
  my $self = shift;
  my $base = shift || $self->base->clone;

  # Relative
  my $rel = $self->clone;
  return $rel unless $rel->is_abs;

  # Different locations
  return $rel
    unless lc $base->scheme eq lc $rel->scheme
      && $base->authority eq $rel->authority;

  # Remove scheme and authority
  $rel->scheme('');
  $rel->authority('');

  # Characters after the right-most '/' need to go
  $rel->base($base->clone);
  my $splice = @{$base->path->parts};
  $splice -= 1 unless $base->path->trailing_slash;
  my $path = $rel->path->clone;
  splice @{$path->parts}, 0, $splice if $splice;
  $rel->path($path);
  $rel->path->leading_slash(0);

  return $rel;
}

# "Dad, what's a Muppet?
#  Well, it's not quite a mop, not quite a puppet, but man... *laughs*
#  So, to answer you question, I don't know."
sub to_string {
  my $self = shift;

  # Scheme and authority
  my $url       = '';
  my $scheme    = $self->scheme;
  my $authority = $self->authority;
  if ($scheme && $authority) {
    $url .= lc "$scheme://";
    $url .= "$authority";
  }

  # Path
  my $path  = $self->path;
  my $slash = $path->leading_slash;
  $path->leading_slash(0) if !$scheme && @{$self->base->path->parts};
  $url .= $path;
  $path->leading_slash($slash);

  # Query
  my $query = $self->query;
  $url .= "?$query" if @{$query->params};

  # Fragment
  if (my $fragment = $self->fragment) {

    # *( pchar / "/" / "?" )
    url_escape $fragment, "$PCHAR\/\?";
    $url .= "#$fragment";
  }

  return $url;
}

1;
__END__

=head1 NAME

Mojo::URL - Uniform Resource Locator

=head1 SYNOPSIS

  use Mojo::URL;

  # Parse
  my $url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:3000/foo/bar?foo=bar#23'
  );
  print $url->scheme;
  print $url->userinfo;
  print $url->host;
  print $url->port;
  print $url->path;
  print $url->query;
  print $url->fragment;

  # Build
  my $url = Mojo::URL->new;
  $url->scheme('http');
  $url->userinfo('sri:foobar');
  $url->host('kraih.com');
  $url->port(3000);
  $url->path('/foo/bar');
  $url->path('baz');
  $url->query->param(foo => 'bar');
  $url->fragment(23);
  print "$url";

=head1 DESCRIPTION

L<Mojo::URL> implements a subset of RFC 3986 and RFC 3987 for Uniform
Resource Locators with support for IDNA and IRIs.

=head1 ATTRIBUTES

L<Mojo::URL> implements the following attributes.

=head2 C<authority>

  my $authority = $url->authority;
  $url          = $url->authority('root:pass%3Bw0rd@localhost:8080');

Authority part of this URL.

=head2 C<base>

  my $base = $url->base;
  $url     = $url->base(Mojo::URL->new);

Base of this URL.

=head2 C<fragment>

  my $fragment = $url->fragment;
  $url         = $url->fragment('foo');

Fragment part of this URL.

=head2 C<host>

  my $host = $url->host;
  $url     = $url->host('127.0.0.1');

Host part of this URL.

=head2 C<port>

  my $port = $url->port;
  $url     = $url->port(8080);

Port part of this URL.

=head2 C<scheme>

  my $scheme = $url->scheme;
  $url       = $url->scheme('http');

Scheme part of this URL.

=head2 C<userinfo>

  my $userinfo = $url->userinfo;
  $url         = $url->userinfo('root:pass%3Bw0rd');

Userinfo part of this URL.

=head1 METHODS

L<Mojo::URL> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $url = Mojo::URL->new;
  my $url = Mojo::URL->new('http://127.0.0.1:3000/foo?f=b&baz=2#foo');

Construct a new L<Mojo::URL> object.

=head2 C<clone>

  my $url2 = $url->clone;

Clone this URL.

=head2 C<ihost>

  my $ihost = $url->ihost;
  $url      = $url->ihost('xn--bcher-kva.ch');

Host part of this URL in punycode format.

=head2 C<is_abs>

  my $is_abs = $url->is_abs;

Check if URL is absolute.

=head2 C<is_ipv4>

  my $is_ipv4 = $url->is_ipv4;

Check if C<host> is an C<IPv4> address.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<is_ipv6>

  my $is_ipv6 = $url->is_ipv6;

Check if C<host> is an C<IPv6> address.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<parse>

  $url = $url->parse('http://127.0.0.1:3000/foo/bar?fo=o&baz=23#foo');

Parse URL.

=head2 C<path>

  my $path = $url->path;
  $url     = $url->path('/foo/bar');
  $url     = $url->path('foo/bar');
  $url     = $url->path(Mojo::Path->new);

Path part of this URL, relative paths will be appended to the existing path,
defaults to a L<Mojo::Path> object.

=head2 C<query>

  my $query = $url->query;
  $url      = $url->query(replace => 'with');
  $url      = $url->query([merge => 'with']);
  $url      = $url->query({append => 'to'});
  $url      = $url->query(Mojo::Parameters->new);

Query part of this URL, defaults to a L<Mojo::Parameters> object.

=head2 C<to_abs>

  my $abs = $url->to_abs;
  my $abs = $url->to_abs(Mojo::URL->new('http://kraih.com/foo'));

Turn relative URL into an absolute one.

=head2 C<to_rel>

  my $rel = $url->to_rel;
  my $rel = $url->to_rel(Mojo::URL->new('http://kraih.com/foo'));

Turn absolute URL into a relative one.

=head2 C<to_string>

  my $string = $url->to_string;

Turn URL into a string.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
