package Koha::Plugin::Com::PTFSEurope::Crossref::Api;

use Modern::Perl;
use strict;
use warnings;

use JSON qw( decode_json );
use LWP::UserAgent;

use Mojo::Base 'Mojolicious::Controller';
use Koha::Plugin::Com::PTFSEurope::Crossref;

sub works {
    # Validate what we've received
    my $c = shift->openapi->valid_input or return;

    my $base_url = "https://api.crossref.org/works/";

    # Check we've got an email address to append to the API call
    # Error if not
    my $email = _get_email();
    $email =~ s/^\s+|\s+$//g;
    if (!$email || length $email == 0) {
        _return_response({ error => 'No email address configured' }, $c);
    }
    my $doi = $c->validation->param('doi') || '';

    if (!$doi || length $doi == 0) {
        _return_response({ error => 'No DOI supplied' }, $c);
    }

    my $ua = LWP::UserAgent->new;
    my $response = $ua->get("${base_url}${doi}?mailto=$email");

    if ( $response->is_success ) {
        _return_response({ success => decode_json($response->decoded_content) }, $c);
    } else {
        _return_response(
            {
                error => $response->status_line,
                errorcode => $response->code
            },
            $c
        );

    }
}

sub parse_to_ill {
    # Validate what we've received
    my $c = shift->openapi->valid_input or return;

    my $body = $c->validation->param('body');

    my $metadata = $body->{message} || {};    

    # Map Koha core ILL props to Crossref
    my $mapping = {
        doi => {
            prop => 'DOI',
            value => sub { return shift; }
        },
        issn => {
            prop => 'ISSN',
            value => sub {
                my $val = shift;
                return ${$val}[0];
            }
        },
        title => {
            prop => 'container-title',
            value => sub {
                my $val = shift;
                return ${$val}[0];
            }
        },
        year => {
            prop => 'published',
            value => sub {
                my $val = shift;
                return $val->{'date-parts'}[0][0];
            }
        },
        issue => {
            prop => 'issue',
            value => sub { return shift; }
        },
        pages => {
            prop => 'page',
            value => sub { return shift; }
        },
        publisher => {
            prop => 'publisher',
            value => sub { return shift; }
        },
        article_title => {
            prop => 'title',
            value => sub { return shift; }
        },
        article_author => {
            prop => 'author',
            value => sub {
                my $val = shift;
                my @authors = ();
                foreach my $author(@{$val}) {
                    push @authors, $author->{given} . " " . $author->{family};
                }
                return join '; ', @authors;
            }
        },
        volume => {
            prop => 'volume',
            value => sub { return shift; }
        },
    };

    my $return = {};

    while (my ($k, $v) = each %{$mapping}) {
        my $crossref_prop_name = $v->{prop};
        if ($metadata->{$crossref_prop_name}) {
            $return->{$k} = $v->{value}->($metadata->{$crossref_prop_name});
        }
    }

    _return_response(
        { success => $return },
        $c
    );
}

sub _return_response {
    my ( $response, $c ) = @_;
    my $to_render = {
        openapi => {
            errors => [],
            results => {
                result => $response->{success} || []
            }
         }
    };
    if ($response->{errorcode} || $response->{error}) {
        $to_render->{openapi}->{errors} = [{
            errorcode => $response->{errorcode},
            message => $response->{error}
        }];
    }
    return $c->render(%{$to_render});
}

sub _get_email {

    my $plugin = Koha::Plugin::Com::PTFSEurope::Crossref->new();
    my $config = decode_json($plugin->retrieve_data("crossref_config") || {});

    return $config->{crossref_email_address};
}

1;