package GrowthForecast::API;

use strict;
use warnings;
use utf8;
use Kossy 0.10;
use Time::Piece;
use GrowthForecast::Data;
use GrowthForecast::RRD;
use Log::Minimal;
use Class::Accessor::Lite ( rw => [qw/short mysql data_dir/] );

sub data {
    my $self = shift;
    $self->{__data} ||= 
        $self->mysql 
            ? GrowthForecast::Data::MySQL->new($self->mysql)
            : GrowthForecast::Data->new($self->data_dir);
    $self->{__data};
}

sub rrd {
    my $self = shift;
    $self->{__rrd} ||= GrowthForecast::RRD->new(
        data_dir => $self->data_dir,
        root_dir => $self->root_dir,
    );
    $self->{__rrd};
}

filter 'get_graph' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        my $row = $self->data->get(
            $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
        );
        $c->halt(404) unless $row;
        $c->stash->{graph} = $row;
        $app->($self,$c);
    }
};

get '/api/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;
    $c->render_json($c->stash->{graph});
};

post '/api/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        'number' => {
            rule => [
                ['NOT_NULL','number is null'],
                ['INT','number must be integer']
            ],
        },
        'mode' => {
            default => 'gauge',
            rule => [
                [['CHOICE',qw/count gauge modified/],'count or gauge or modified']
            ],
        },
        'color' => {
            default => '',
            rule => [
                [sub{ length($_[1]) == 0 || $_[1] =~ m!^#[0-9A-F]{6}$!i }, 'invalid color code'],
            ],
        },

    ]);

    if ( $result->has_error ) {
        my $res = $c->render_json({
            error => 1,
            messages => $result->messages
        });
        $res->status(400);
        return $res;
    }

    my $row;
    eval {
        $row = $self->data->update(
            $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
            $result->valid('number'), $result->valid('mode'), $result->valid('color')
        );
    };
    if ( $@ ) {
        die sprintf "Error:%s %s/%s/%s => %s,%s,%s", 
            $@, $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
                $result->valid('number'), $result->valid('mode'), $result->valid('color');
    }
    $c->render_json({ error => 0, data => $row });
};

1;

