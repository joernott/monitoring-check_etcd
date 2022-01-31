#!/bin/bash
SCRIPT=$0

function log() {
    local LEVEL=$1
    if [ ${LEVEL} -le ${LOGLEVEL} ]; then
        shift 1
        local DATE=$(date +"%Y-%m-%d %H:%M:%S")
        printf "%s %s %s\n" "${DATE}" "${LOGLEVEL_TEXT[${LEVEL}]}" "$@"
    fi
}

function usage() {
        cat <<EOF
Usage: build.sh <VERSION> [<RELEASE>]

where VERSION is the version number of the github release and RELEASE the
release number. If RELEASE is omitted, it defaults to 1.

EOF
}

function get_version() {
    local PACKAGE=$1
    local DATA=$(yum info --enablerepo="*" $PACKAGE 2>/dev/null)
    local V=$(echo $DATA|grep -e "^Version\s*:\s*"|sed -e 's|.*\s||')
    local R=$(echo $DATA|grep -e "^Release\s*:\s*"|sed -e 's|.*\s||')
    COMBINED="$V-$R"
}

function init() {
    RPMBUILD_DIR=$(dirname "${SCRIPT}")
    SPECS_DIR=${RPMBUILD_DIR}/SPECS
    RPMS_DIR=${RPMBUILD_DIR}/RPMS
    SRPMS_DIR=${RPMBUILD_DIR}/SRPMS
    BUILD_DIR=${RPMBUILD_DIR}/BUILD
    SOURCES_DIR=${RPMBUILD_DIR}/SOURCES
    LOGLEVEL=5
    LOGLEVEL_TEXT[0]="Panic"
    LOGLEVEL_TEXT[1]="Fatal"
    LOGLEVEL_TEXT[2]="Error"
    LOGLEVEL_TEXT[3]="Warning"
    LOGLEVEL_TEXT[4]="Info"
    LOGLEVEL_TEXT[5]="Debug"
    VERSION=""
    RELEASE=""
    VALIDATE=0
    FETCH=1
}

function check() {
    for DIR in ${SPECS_DIR} ${RPMS_DIR} ${SRPMS_DIR} ${BUILD_DIR} ${SOURCES_DIR}; do
        if [ ! -d ${DIR} ]; then
            log 1 "$DIR not found. This should be part of the rpmbuild git checkout"
            exit 1
        fi
    done

    for V in VERSION RELEASE; do
        if [ -z "${!V}" ]; then
            log 1 "${V} not set. You must provide all versions/revisions"
            exit 2
        fi
    done
    if [ $VALIDATE -gt 0 ]; then
        get_version icinga_check_etcd
        if [ "${COMBINED}" == "${VERSION}-${RELEASE}" ]; then
            log 1 "There is already a icinga_check_etcd RPM with version ${VERSION} and release ${RELEASE}. Bump version/release before rebuilding."
            exit 3
        fi
    fi
}

function get_archives() {
    if [ $FETCH -gt 0 ]; then
        log 5 Fetch check_etcd-${VERSION}
        if [ -f check_etcd-${VERSION}.tar.gz ]; then
            log 4 Using already fetched check_etcd-${VERSION}
        else
            curl -sSjL "https://github.com/joernott/check_etcd/archive/refs/tags/v${VERSION}.tar.gz" -o "${SOURCES_DIR}/check_etcd-${VERSION}.tar.gz"
        fi
    fi
}

function build() {
    cd ${RPMBUILD_DIR}
    log 4 "Building icinga_check_etcd ${CHECK_BIGIP_VERSION}-${CHECK_BIGIP_RELEASE}"
    rpmbuild --define "_topdir $(pwd)" \
             --define "version ${VERSION}" \
             --define "release ${RELEASE}" \
             --define "user ${USER}" \
             -ba ${SPECS_DIR}/icinga_check_etcd.spec
}

#### Main ####
init
if [ -n "$1" ]; then
    VERSION=$1
    shift
fi
if [ -n "$1" ]; then
    RELEASE=$1
    shift
else
    RELEASE=1
fi
check
get_archives
build
