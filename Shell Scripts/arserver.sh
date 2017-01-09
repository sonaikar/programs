#
# when this server changes, make sure that arserver.sh is updated
# in ALL other ITSM apps - Asset, Change, Helpdesk, SLA. It is used to 
# pull the workflow, which each app overwrites
#
# main - English application
ARSERVER=vm1-w23-prem75
ARUSER=builddev
ARPASSWD=Asimil8
ARPORT=0
export ARSERVER ARUSER ARPASSWD

# Japanese
	# views
	ARSERVER_ja=Asset
	ARUSER_ja=build
	ARPASSWD_ja=build

# German
	# views
	ARSERVER_de=Asset
	ARUSER_de=build
	ARPASSWD_de=build

# French
	# views
	ARSERVER_fr=Asset
	ARUSER_fr=build
	ARPASSWD_fr=build

# Reconciliation Engine master servers
RE_ARSERVER="$ARSERVER"
RE_ARUSER="$ARUSER"
RE_ARPASSWD="$ARPASSWD"
RE_ARPORT="$ARPORT"
export RE_ARSERVER RE_ARUSER RE_ARPASSWD

# DSL Master Server
DSL_ARSERVER=vm-w23-rds184
DSL_ARUSER=snap_user
DSL_ARPASSWD=Domino
DSL_ARPORT=0

export DSL_ARSERVER DSL_ARUSER DSL_ARPASSWD DSL_ARPORT
