package DBI::Forward::Execute;

#   $Id$
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

use DBI;
use DBI::Forward::Request;
use DBI::Forward::Response;

use base qw(Exporter);

our $VERSION = sprintf("0.%06d", q$Revision$ =~ /(\d+)/o);

our @EXPORT_OK = qw(
    execute_request
    execute_dbh_request
    execute_sth_request
);

our @sth_std_attr = qw(
    NUM_OF_PARAMS
    NUM_OF_FIELDS
    NAME
    TYPE
    NULLABLE
    PRECISION
    SCALE
    CursorName
);

# XXX tracing

sub _connect {
    my $request = shift;
    local $ENV{DBI_AUTOPROXY};
    my $connect_args = $request->connect_args;
    my ($dsn, $u, $p, $attr) = @$connect_args;
    # XXX need way to limit/purge connect cache over time
    my $dbh = DBI->connect_cached($dsn, $u, $p, {
        %$attr,
        # override some attributes
        PrintWarn  => 0,
        PrintError => 0,
        RaiseError => 1,
    });
    #$dbh->trace(0);
    return $dbh;
}


sub _reset_dbh {
    my ($dbh) = @_;
    $dbh->set_err(undef, undef); # clear any error state
    #$dbh->trace(0, \*STDERR);
}


sub _new_response_with_err {
    my ($rv) = @_;

    my ($err, $errstr, $state) = ($DBI::err, $DBI::errstr, $DBI::state);
    if ($@ and !$errstr || $@ !~ /^DBD::/) {
        $err ||= 1;
        $errstr = ($errstr) ? "$errstr; $@" : $@;
    }
    my $response = DBI::Forward::Response->new({
        rv     => $rv,
        err    => $err,
        errstr => $errstr,
        state  => $state,
    });
    return $response;
}


sub execute_request {
    my $request = shift;
    my $response = eval {
        ($request->is_sth_request)
            ? execute_sth_request($request)
            : execute_dbh_request($request);
    };
    if ($@) {
        warn $@; # XXX
        $response = DBI::Forward::Response->new({
            err => 1, errstr => $@, state  => '',
        });
    }
    return $response;
}

sub execute_dbh_request {
    my $request = shift;
    my $dbh;
    my $rv_ref = eval {
        $dbh = _connect($request);
        my $meth = $request->dbh_method_name;
        my $args = $request->dbh_method_args;
        my @rv = ($request->dbh_wantarray)
            ?        $dbh->$meth(@$args)
            : scalar $dbh->$meth(@$args);
        \@rv;
    };
    my $response = _new_response_with_err($rv_ref);
    if ($dbh) {
        $response->last_insert_id = $dbh->last_insert_id( @{ $request->dbh_last_insert_id_args })
            if $rv_ref && $request->dbh_last_insert_id_args;
        _reset_dbh($dbh);
    }
    if ($rv_ref and UNIVERSAL::isa($rv_ref->[0],'DBI::st')) {
        my $rv = $rv_ref->[0];
        # dbh_method_call was probably a metadata method like table_info
        # that returns a statement handle, so turn the $sth into resultset
        $response->sth_resultsets( _gather_sth_resultsets($rv, $request) );
        $response->rv("(sth)");
    }
    return $response;
}


sub execute_sth_request {
    my $request = shift;
    my $dbh;
    my $sth;

    my $rv = eval {
        $dbh = _connect($request);

        my $meth = $request->dbh_method_name;
        my $args = $request->dbh_method_args;
        $sth = $dbh->$meth(@$args);
        my $last = '(sth)'; # a true value

        # execute methods on the sth, e.g., bind_param & execute
        for my $meth_call (@{ $request->sth_method_calls }) {
            my $method = shift @$meth_call;
            $last = $sth->$method(@$meth_call);
        }
        $last;
    };
    my $response = _new_response_with_err($rv);

    # even if the eval failed we still want to try to gather attribute values
    $response->sth_resultsets( _gather_sth_resultsets($sth, $request) ) if $sth;

    # XXX would be nice to be able to support streaming of results
    # which would reduce memory usage and latency for large results

    _reset_dbh($dbh) if $dbh;

    return $response;
}


sub _gather_sth_resultsets {
    my ($sth, $request) = @_;
    return eval {
        my $attr_list = $request->sth_result_attr;
        $attr_list = [ keys %$attr_list ] if ref $attr_list eq 'HASH';
        my $rs_list = [];
        do {
            my $rs = fetch_result_set($sth, $attr_list);
            push @$rs_list, $rs;
        } while $sth->more_results;

        $rs_list;
    };
}


sub fetch_result_set {
    my ($sth, $extra_attr) = @_;
    my %meta;
    for my $attr (@sth_std_attr, @$extra_attr) {
        $meta{ $attr } = $sth->{$attr};
    }
    if ($sth->FETCH('NUM_OF_FIELDS')) { # if a select
        $meta{rowset} = eval { $sth->fetchall_arrayref() };
        $meta{err}    = $DBI::err;
        $meta{errstr} = $DBI::errstr;
        $meta{state}  = $DBI::state;
    }
    return \%meta;
}

1;