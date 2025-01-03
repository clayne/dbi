# NAME

DBD::Multiplex - A multiplexing driver for the DBI.

# SYNOPSIS

    use strict;

    use DBI;

    my ($dsn1, $dsn2, $dsn3, $dsn4, %attr);

    # Define four databases, in this case, four Postgres databases.

    $dsn1 = 'dbi:Pg:dbname=aaa;host=10.0.0.1;mx_id=db-aaa-1';
    $dsn2 = 'dbi:Pg:dbname=bbb;host=10.0.0.2;mx_id=db-bbb-2';
    $dsn3 = 'dbi:Pg:dbname=ccc;host=10.0.0.3;mx_id=db-ccc-3';
    $dsn4 = 'dbi:Pg:dbname=ddd;host=10.0.0.4;mx_id=db-ddd-4';

    # Define a callback error handler.

    sub MyErrorProcedure {
           my ($dsn, $mx_id, $error_number, $error_string, $h) = @_;
           open TFH, ">>/tmp/dbi_mx$mx_id.txt";
           print TFH localtime().": $error_number\t$error_string\n";
           close TFH;
           return 1;
    }

    # Define the pool of datasources.

    %attr = (
           'mx_dsns' => [$dsn1, $dsn2, $dsn3, $dsn4],
           'mx_master_id' => 'db-aaa-1',
           'mx_connect_mode' => 'ignore_errors',
           'mx_exit_mode' => 'first_success',
           'mx_error_proc' => \&MyErrorProcedure,
    );

    # Connect to all four datasources.

    $dbh = DBI->connect("dbi:Multiplex:", 'username', 'password', \%attr);

    # See the DBI module documentation for full details.

# DESCRIPTION

DBD::Multiplex is a Perl module which works with the DBI allowing you
to work with multiple datasources using a single DBI handle.

Basically, DBD::Multiplex database and statement handles are parents
that contain multiple child handles, one for each datasource. Method
calls on the parent handle trigger corresponding method calls on
each of the children.

One use of this module is to mirror the contents of one datasource
using a set of alternate datasources.  For that scenario it can
write to all datasources, but read from only from one datasource.

Alternatively, where a database already supports replication,
DBD::Multiplex can be used to direct writes to the master and spread
the selects across multiple slaves.

Another use for DBD::Multiplex is to simplify monitoring and
management of a large number of databases, especially when combined
with DBI::Shell.

# COMPATIBILITY

A goal of this module is to be compatible with DBD::Proxy / DBI::ProxyServer.
Currently, the 'mx\_error\_proc' feature generates errors regarding the storage
of CODE references within the Storable module used by RPC::PlClient
which in turn is used by DBD::Proxy. Yet it works.

# CONNECTING TO THE DATASOURCES

Multiple datasources are specified in the either the DSN parameter of
the DBI->connect() function (separated by the '|' character),
or in the 'mx\_dsns' key/value pair (as an array reference) of
the \\%attr hash parameter.

# SPECIFIC ATTRIBUTES

The following specific attributes can be set when connecting:

- **mx\_dsns**

    An array reference of DSN strings.

- **mx\_master\_id**

    Specifies which mx\_id will be used as the master server for a
    master/slave one-way replication scheme.

- **mx\_connect\_mode**

    Options available or under consideration:

    **report\_errors**

    A failed connection to any of the data sources will generate a DBI error.
    This is the default.

    **ignore\_errors**

    Failed connections are ignored, forgotten, and therefore, unused.

- **mx\_exit\_mode**

    Options available or under consideration:

    **first\_error**

    Execute the requested method against each child handle, stopping
    after the first error, and returning the all of the results.
    This is the default.

    **first\_success**

    Execute the requested method against each child handle, stopping after
    the first successful result, and returning only the successful result.
    Most appropriate when reading from a set of mirrored datasources.

    **last\_result**

    Execute the requested method against each child handle, not stopping after
    any errors, and returning all of the results.

    **last\_result\_most\_common**

    Execute the requested method against each child handle, not stopping after
    the errors, and returning the most common result (eg three-way-voting etc).
    Not yet implemented.

- **mx\_shuffle**

    Shuffles the list of child handles each time it's about to be used.
    Typically combined with an `mx_exit_mode` of '`first_success`'.

- **mx\_shuffle\_connect**

    Like `mx_shuffle` above but only applies to connect().

- **mx\_error\_proc**

    A reference to a subroutine which will be executed whenever a DBI method
    generates an error when working with a specific datasource. It will be
    passed the DSN and 'mx\_id' of the datasource, and the $DBI::err and $DBI::errstr.

    Define your own subroutine and pass a reference to it. A simple
    subroutine that just prints the dsn, mx\_id, and error details to STDERR
    can be selected by setting mx\_error\_proc to the string 'DEFAULT'.

In some cases, the exit mode will depend on the method being called.
For example, this module will always execute $dbh->disconnect() calls
against each child handle.

In others, the default will be used, unless the user of the DBI
specified the 'mx\_exit\_mode' when connecting, or later changed
the 'mx\_exit\_mode' attribute of a database or statement handle.

# USAGE EXAMPLE

Here's an example of using DBD::Multiplex with MySQL's replication scheme.

MySQL supports one-way replication, which means we run a server as the master
server and others as slaves which catch up any changes made on the master.
Any READ operations then may be distributed among them (master and slave(s)),
whereas any WRITE operation must _only_ be directed toward the master.
Any changes happened on slave(s) will never get synchronized to other servers.
More detailed instructions on how to arrange such setup can be found at:

http://www.mysql.com/documentation/mysql/bychapter/manual\_Replication.html

Now say we have two servers, one at 10.0.0.1 as a master, and one at
10.0.0.9 as a slave. The DSN for each server may be written like this:

    my @dsns = qw{
           dbi:mysql:database=test;host=10.0.0.1;mx_id=masterdb
           dbi:mysql:database=test;host=10.0.0.9;mx_id=slavedb
    };

Here we choose easy-to-remember `mx_id`s: masterdb and slavedb.
You are free to choose alternative names, for example: mst and slv.
Then we create the DSN for DBD::Multiplex by joining them, using the
pipe character as separator:

    my $dsn = 'dbi:Multiplex:' . join('|', @dsns);
    my $user = 'username';
    my $pass = 'password';

As a more paranoid practice, configure the 'user's permissions to
allow only SELECTs on the slaves.

Next, we define the attributes which will affect DBD::Multiplex behaviour:

    my %attr = (
           'mx_master_id' => 'masterdb',
           'mx_exit_mode' => 'first_success',
           'mx_shuffle'    => 1,
    );

These attributes are required for MySQL replication support:

We set `mx_shuffle` true which will make DBD::Multiplex shuffle the
DSN list order prior to connect, and shuffle the

The `mx_master_id` attribute specifies which `mx_id` will be recognized
as the master. In our example, this is set to 'masterdb'. This attribute will
ensure that every WRITE operation will be executed only on the master server.
Finally, we call DBI->connect():

    $dbh = DBI->connect($dsn, $user, $pass, \%attr) or die $DBI::errstr;

# LIMITATIONS AND BUGS

A HandleError sub is only invoked on the multiplex handle, not the
child handles and can't alter the return value.

The Name attribute may change in content in future versions.

The AutoCommit attribute doesn't appear to be affected by the begin\_work
method. That's one symptom of the next item:

Attributes may not behave as expected because the DBI intercepts
attribute FETCH calls and returns the value, if there is one, from
DBD::Multiplex's attribute cache and doesn't give DBD::Multiplex a
change to multiplex the FETCH. That's fixed from DBI 1.36.

# AUTHORS AND COPYRIGHT

Copyright (c) 1999,2000,2003, Tim Bunce & Thomas Kishel

While I defer to Tim Bunce regarding the majority of this module,
feel free to contact me for more information:

        Thomas Kishel
        Larson Texts, Inc.
        1760 Norcross Road
        Erie, PA 16510
        tkishel@tdlc.com
        814-461-8900

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.
