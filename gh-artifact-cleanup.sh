#!/bin/sh
# Locate artifacts for runs against orphaned commit revisions.  This tends to
# be a result of developers pushing changes to a pull-request triggering
# re-runs of the pull request.

set -e
# utility
lines() { output "${*}" | wc -l ; }
# safely deal with content which may begin w/ a hyphen
output() { printf '%s' "${*}"; }
usage()
{
	if test "$#" -gt '0'; then
		error "$*"
		echo "try '$0 --help'" >&2
		exit 1
	fi

	sed -e 's/^	//'<<END_OF_USAGE
	usage: $0 [options]
	options:
	  -N, --newer NUM	Limit to runs that are newer than NUM days ago.
	  -O, --older NUM	Limit to runs that are older than NUM days ago.
	  -n, --dry-run		Report what would be done, do not make any changes.
	  -x, --trace		Enable execution tracing.
	  -h, --help		Display this help.

END_OF_USAGE

	# Requests for help are not an error
	exit 0
}

# make dealing with string escapes easier
jq_count() { output "${*}" | jq 'def count(s): reduce s as $_ (0;.+1); count(.[])'; }
jq_query()
{
	test -n "${1}" || return 1
	__jq_query_data="${1}"
	shift
	# shellcheck disable=SC2059
	set -- "${__jq_query_data}" "$(printf "${@}")"
	unset __jq_query_data
	output "${1}" | jq -r "${2}"
}

REPOS_SEEN=
git_is_tip()
{
	if ! output "${REPOS_SEEN}" | grep -q "${2}"; then
		REPOS_SEEN="$(printf '%s%s\n' "${REPOS_SEEN}" "${2}")"
		set -- "${@}" "$(lines "${REPOS_SEEN}")" "$(gh api "${2}" --jq '.clone_url')"
		if test "$(git remote get-url origin)" != "${4}"; then
			git remote add "origin-${3}" "${4}" || :
			git fetch "origin-${3}" || :
		fi
	fi

	points_at="$(git branch -a --list --points-at "${1}" | sed -e 's/^[*]//')"
	if test -n "${points_at}"; then
		printf '%s' "${points_at}" | while read -r ref; do
			printf '::notice::SKIPPING: %s@%s\n' "${1}" "${ref## }"
		done
		return
	fi
	return 1
}

NEWER=
OLDER=
DRY_RUN='false'
while test "$#" -gt '0'; do
	case "${1}" in
	(-N|--newer)	NEWER="$(date --date "${2} days ago" '+%Y-%m-%d')"; shift;;
	(-O|--older)	OLDER="$(date --date "${2} days ago" '+%Y-%m-%d')"; shift;;
	(-n|--dry-run)	DRY_RUN='true';;
	(-x|--trace)	set -x;;
	(-h|--help)	usage;;
	(--)		shift; break;;
	(-*)		usage "unknown option '${1}'";;
	(*)		break;;
	esac
	shift
done

created=
if test -n "${NEWER}" && test -n "${OLDER}"; then
	created="&created=${NEWER}..${OLDER}"
elif test -n "${NEWER}"; then
	created="&created=>${NEWER}"
elif test -n "${OLDER}"; then
	created="&created=<${OLDER}"
fi

HASH_SEEN=
page='1'
run_ids="$(gh api "repos/{owner}/{repo}/actions/runs?page=${page}${created}" --jq '.workflow_runs[].id')"
while test -n "${run_ids}"; do
	for run_id in ${run_ids}; do
		run_data="$(gh api "repos/{owner}/{repo}/actions/runs/${run_id}")"

		# Check to see if has a PR and if so was it already merged/accepted
		count="$(jq_count "$(jq_query "${run_data}" '.pull_requests')")"
		if test "${count}" != '0'; then
			index='0'
			while test "${index}" -lt "${count}"; do
				pr_data="$(jq_query "${run_data}" '.pull_requests[%s]' "${index}")"
				pr_sha="$(jq_query "${pr_data}" '.head.sha')"
				pr_url="$(jq_query "${pr_data}" '.head.repo.url')"
				index="$((index+1))"

				! output "${HASH_SEEN}" | grep -q "${pr_sha}" || continue
				HASH_SEEN="$(printf '%s%s\n' "${HASH_SEEN}" "${pr_sha}")"
				! git_is_tip "${pr_sha}" "${pr_url}" || continue 2
			done
		else
			sha="$(jq_query "${run_data}" '.head_commit.id')"
			url="$(jq_query "${run_data}" '.head_repository.url')"

			! output "${HASH_SEEN}" | grep -q "${sha}" || continue
			HASH_SEEN="$(printf '%s%s\n' "${HASH_SEEN}" "${sha}")"
			! git_is_tip "${sha}" "${url}" || continue
		fi

		artifact_ids="$(gh api "repos/{owner}/{repo}/actions/runs/${run_id}/artifacts" --jq '.artifacts[].id')"
		if test -n "${artifact_ids}"; then
			echo "::group::Inspecting run-id ${run_id}"
			for artifact in $(gh api "repos/{owner}/{repo}/actions/runs/${run_id}/artifacts" --jq '.artifacts[].id'); do
				echo "::notice::DELETE: repos/{owner}/{repo}/actions/artifacts/${artifact}"
				"${DRY_RUN}" || gh api -XDELETE "repos/{owner}/{repo}/actions/artifacts/${artifact}"
			done
			echo '::endgroup::'
		fi
	done
	page="$((page+1))"
	run_ids="$(gh api "repos/{owner}/{repo}/actions/runs?page=${page}${created}" --jq '.workflow_runs[].id')"
done
