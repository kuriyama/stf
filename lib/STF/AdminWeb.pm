package STF::AdminWeb;
use strict;
use Class::Load ();
use HTML::FillInForm;
use STF::Constants;
use STF::Context;
use STF::AdminWeb::Context;
use Class::Accessor::Lite
    new => 1,
    rw => [ qw(
        context
        router
        stf_base
        default_view_class
        use_reverse_proxy
        htdocs
    ) ]
;

sub bootstrap {
    my $class = shift;
    my $context = STF::Context->bootstrap(@_);

    # These are the default values
    my $use_reverse_proxy = 
        # if USE_REVERSE_PROXY exists, use that value
        exists $ENV{USE_REVERSE_PROXY} ?  $ENV{USE_REVERSE_PROXY} :
        # if PLACK_ENV is production, then use reverse proxy
        $ENV{PLACK_ENV} eq 'production' ? 1 :
        # otherwise no
        0
    ;
    my $htdocs = File::Spec->catfile( $ENV{STF_HOME} || $ENV{DEPLOY_HOME} || Cwd::cwd(), "htdocs" );

    my $app = STF::AdminWeb->new(
        use_reverse_proxy => $use_reverse_proxy,
        htdocs => $htdocs,
        %{ $context->get('config')->{'AdminWeb'} || {} },
        context => $context,
        router  => $context->get('AdminWeb::Router'),
    );

    return $app;
}

sub to_app {
    my $self = shift;

    my $app = sub {
        my $env = shift;
        $self->handle_psgi($env);
    };
    if ($self->use_reverse_proxy) {
        require Plack::Middleware::ReverseProxy;
        return Plack::Middleware::ReverseProxy->wrap( $app );
    } else {
        require Plack::Middleware::Static;
        return Plack::Middleware::Static->wrap( $app, (
            path => qr{^/static},
            root => $self->htdocs,
        ) );
    }
}

sub handle_psgi {
    my ($self, $env) = @_;

    my $context = $self->context;
    my $rc = STF::AdminWeb::Context->new(
        env => $env,
        container => $context->container,
    );
    my $guard = $context->container->new_scope();

    eval {
        $self->dispatch( $rc, $env );
    };
    if (my $e = $@) {
        if ($e !~ /^stf\.abort/) {
            $self->handle_server_error($rc, $e);
        }
    }

    return $rc->response->finalize();
}

sub handle_not_found {
    my ($self, $c, $message) = @_;

    my $response = $c->response;
    $response->code( 404 );
    $response->content_type( "text/plain" );
    $response->body( $message ) if $message;
}

sub handle_server_error {
    my ($self, $c, $message) = @_;

    my $response = $c->response;
    $response->code( 500 );
    $response->content_type( "text/plain" );
    $response->body( $message ) if $message;
}

sub dispatch {
    my ($self, $context, $env) = @_;

    my $h = $self->router->match( $env );
    if (! $h) {
        # 404
        $self->handle_not_found( $context );
        return;
    }

    $context->match( $h );
    my $action = $h->{action};
    my $controller_class = $h->{controller};
    my $controller = $self->get_component(
        $controller_class, 'STF::AdminWeb::Controller' );

    $controller->execute( $context, $action );
    if (! $context->finished) {
        $self->render( $context, $controller, $action );
    }

    my $req = $context->request;
    my $res = $context->response;
    if ($res->content_type && $res->content_type =~ m{^text/x?html$}i) {
        if ( $req->method eq 'POST' ) {
            my $body = $res->body;
            $res->body( HTML::FillInForm->fill( \$body, $req ) );
        } elsif ( my $fdat = $context->stash->{fdat} ) {
            my $body = $res->body;
            $res->body( HTML::FillInForm->fill( \$body, $fdat ) );
        }
    }
}

sub get_component {
    my ($self, $klass, $prefix) = @_;

    if ( $klass !~ s/^\+// ) {
        if (! $prefix) { Carp::croak( "No prefix provided" ) }
        $klass = join '::', $prefix, $klass;
    }

    my $component;
    {
        local $@;
        $component = eval { $self->context->get( $klass ) };
    }
    if ($component) {
        return $component;
    }

    Class::Load::load_class($klass) unless
        Class::Load::is_class_loaded($klass);

    my $key = $klass;
    $key =~ s/^STF:://;
    my $config = $self->context->config->{$key} || {};

    $component = $klass->new( %$config, app => $self);
    $self->context->container->register( $key => $component );

    return $component;
}

sub render {
    my ($self, $context, $controller, $action) = @_;

    my $stash = $context->stash;
    my $template = $stash->{template} ||
        join( '/', do {
            my @list = ($action);
            unshift @list, $controller->namespace if $controller->namespace;
            @list
        } )
    ;

    my $view_class = $stash->{view_class} ||
        $controller->view_class ||
        $self->default_view_class
    ;
    my $view = $self->get_component( $view_class, 'STF::AdminWeb::View' );
    if (! $view) {
        die "No view found";
    }


    $stash->{c} = $context;
    $stash->{const} = STF::Constants::as_hashref();
    $stash->{stf_base} = $self->stf_base;
    $view->process( $context, $template );
}

1;
