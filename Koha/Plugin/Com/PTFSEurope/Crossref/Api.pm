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

sub _return_response {
    my ( $response, $c ) = @_;
    return $c->render(
        status => $response->{errorcode} || 200,
        openapi => {
            results => {
                result => $response->{success} || [],
                errors => $response->{error} || []
            }
        }
    );
}

sub _get_email {

    my $plugin = Koha::Plugin::Com::PTFSEurope::Crossref->new();
    my $config = decode_json($plugin->retrieve_data("crossref_config") || {});

    return $config->{crossref_email_address};
}

1;