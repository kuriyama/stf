package STF::AdminWeb::Controller::Object;
use strict;
use parent qw(STF::AdminWeb::Controller);

sub view_public_name {
    my ($self, $c) = @_;
    my ($bucket_name, $object_name) = @{ $c->match->{splat} || [] };

    my $bucket = $c->get('API::Bucket')->lookup_by_name($bucket_name);
    if (! $bucket) {
        my $response = $c->response;
        $response->status(404);
        $c->abort();
    }

    my $object_id = $c->get('API::Object')->find_object_id( {
        bucket_id => $bucket->{id},
        object_name => $object_name
    } );
    if (! $object_id) {
        my $response = $c->response;
        $response->status(404);
        $c->abort();
    }

    $c->match->{object_id} = $object_id;
    $c->stash->{template} = 'object/view';
    $self->view($c);
}

sub view {
    my ($self, $c) = @_;

    my $object_id = $c->match->{object_id};
    my ($object) = $c->get('API::Object')->search_with_entity_info(
        { id => $object_id },
        { limit => 1 }
    );
    my $bucket = $c->get('API::Bucket')->lookup( $object->{bucket_id} );

    my $limit = 100;
    my $pager = $c->pager($limit);

    my @entities = $c->get('API::Entity')->search_with_url(
        { object_id => $object->{id} },
        { order_by => \'status DESC' },
    );

    my $stash = $c->stash;
    $stash->{bucket} = $bucket;
    $stash->{object} = $object;
    $stash->{pager} = $pager;
    $stash->{entities} = \@entities;
}


1;