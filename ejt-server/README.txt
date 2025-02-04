INSTALLATION NOTES:

I. ENTERING LICENSE KEYS

The file license.txt must exist in the working directory and must contain at
least one valid floating license for the license server to start up 
successfully. Each license key must be entered on a separate line.

The executable named "updateLicenseKeys" starts a UI where you can modify the
license keys. The license server will be restarted upon completion in order
to apply the new license keys.

II. STARTING THE LICENSE SERVER

The license server is started with the executable in the bin directory.
By default, the license server uses the port 11862. If you would like to
use a non-default port for the service, please specify that port in
bin/ejtserver.vmoptions. In the same file, you can also bind the
license server to a specific IP address (only applicable if you have
multiple local IP addresses).

1. Microsoft Windows

On Microsoft Windows, the license server is started with the service
executable ejtserver.exe. It has the following options:

    /start          starts the service
    /stop           stops the service
    /install        installs the service. It will be started at boot time.
                    You can optionally specify a service name as the next 
                    parameter
    /uninstall      uninstalls the service. If you have installed the 
                    service with a non-default name, you have to specify 
                    that name as the next parameter.

Command line installation requires elevated privileges, so you have to invoke
ejtserver.exe with the above arguments from a terminal with Administrator
rights.

2. Unix, Linux

On Unix-like platforms, the license server is started with the daemon launch
script ejtserver that can be easily integrated into the boot sequence. It has
the following options:

    start          starts the license server
    stop           starts the license server
    
3. macOS

On macOS, the license server is started with the daemon launch script
ejtserver. The installer integrates it into the boot sequence as a startup
item. It has the following options:

    start          starts the license server
    stop           starts the license server


III. USING FLOATING LICENSES:

ej-technologies' products offer a floating license mode in the license dialog.
Choose Help->Enter License Key from the main menu in the JProfiler GUI or the 
install4j IDE and select the "On-premise license server" radio button.

The "Name" and "Company" fields are informational only unless you choose to
restrict the allowed values for the "Name" field as described in README.TXT.
In the license server field, you have to enter the hostname of the computer
where the license server is running. Instead of a host name, an IP address can
also be used.

By default, the license server protocol is authenticated and encrypted. When
the license server first starts, it generates server and client authentication
files in the "encryption" subdirectory.

You then have to distribute the file encryption/client.ks to all users. They
can configure this file in the license entry dialog.

The connection is secured by TLS with mutual authentication between server and
client. To reset authentication, you can delete the files in the "encryption"
subdirectory and new files will be generated during the next startup.

Note that encryption requires at least JProfiler 12.0.2 or install4j 9.0.1
on the client side. Older versions will not be able to connect to the
license server if encryption is enabled.

You can disable encryption by copying config.properties.template to
config.properties and uncommenting the line

encrypted=false

If you have a floating license for a certain major version of a product, you
can use older versions of the same product with that floating license as well.

Should you require any additional assistance, please contact

    support@ej-technologies.com
	
IV. USING THE ADMIN TOOL

The bin directory of the license server distribution contains an executable 
named admin that allows you to connect to a running license server. The
connection will only be allowed if the tool is executed on the local 
computer. Connections from a remote computer are not possible.

If the license server is running on a non-default port, please specify

-port <port number>

as an argument to change the port. If the license server is bound to a
specific IP address, please use the 

-ip nnn.nnn.nnn.nnn

as an argument to change the IP address.

The admin tool is command line-based, it allows you to list all active
connections and to terminate selected connections. In addition, you
can check out a temporary license for use in environments that
have no access to the floating license server.

V. LOGGING

The license server uses logback for logging information and error messages.
You can configure logging with the 

logback.properties

configuration file. By default, the location of the log file is

log/server.log

For more information on how to configure logback, please see

https://logback.qos.ch/manual/index.html

If there is an error during startup before the logging mechanism is 
initialized, a file 

log/stderr.log

is written with the exception or error message.

VI. ACCESS CONTROL

You can restrict what usernames can connect to the license server.
Please see the file 

users.txt 

configuration file for more information.

You can restrict what IP addresses can connect to the license server.
Please see the file 

ip.txt 

configuration file for more information. The most secure way to manage
access control is to use SSH tunneling. In that case, add 127.0.0.1 to that
file, so that only local connections are allowed. Users can configure
the SSH tunnel directly in the license entry dialog and do not need any
additional software.

If you need to block parts of the set of allowed IP addresses, add them
to the file

blocked_ip.txt

See that file for more information.

VII. USER GROUPS

If you want to partition keys to different groups of users, you can define
groups in the file license.txt and the access control files users.txt
and ip.txt by inserting group headers:

   [group]

All entries after a group header belong to that group until a new group is
started. If no group has been started, entries are added to the "default"
group.

Users are assigned to a group based on the defined groups in the access
control files. If users are defined in users.txt, the group is determined
by the that file. If the resulting group is the default group, the ip.txt
file will be used for determining the associated group. If the users.txt file
is empty, only the ip.txt file will be used.

In order to partition a single key to different groups in the license.txt
file, add the key to multiple groups with the following syntax:

   n:key

where n is the number of concurrent users that should be assigned to the
current group. Use different values of n in different groups that add up to
the maximum number of current users for the key. For example:

[groupA]
4:F-95-10-xxx
[groupB]
6:F-95-10-xxx

splits the 10-user key F-95-10-xxx into 4 concurrent users for [groupA] and
6 concurrent users for [groupB]. In users.txt, the groups would be defined as:

[groupA]
bob
alice
...


[groupB]
carol
john
...

Alternatively, the ip.txt file could define groups as

[groupA]
192.162.1.*
[groupB]
192.162.2.*

Group names are shown in the log file next to the username.

VIII. DOCKER

You can generate a Docker image from your license server installation by
executing

docker build -f Dockerfile.external_keys . -t ejtserver

in the configured installation directory. This image will include your
configuration except the sensitive encryption and license keys. This
information can be passed to the container with environment variables.
The file

encryption/keys.env

contains the encryption keys that are generated during the first startup. That
file can be passed to Docker with the --env-file parameter.

License keys can be passed with the variable EJTSERVER_LICENSES, multiple keys
are separated by commas.

As an alternative, there is a Dockerfile that will include all encryption keys
as well as the license keys. You can use it if you are using an internal
repository that you can safely publish sensitive information to. Build this
image with

docker build -f Dockerfile.included_keys . -t ejtserver

When you run the Docker container, you have to publish port 11862. You can
modify the Dockerfiles and docker/entrypoint.sh according to your needs. An
example command to try out the server interactively is

docker run -e "EJTSERVER_LICENSES=<your key>" --env-file encryption/keys.env -p 11862:11862 ejtserver