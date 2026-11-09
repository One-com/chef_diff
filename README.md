# Chef Diff

## Intro

Chef Diff is a library for calculating what Chef objects were modified 
between two revisions in Chef Git repo. Chef Diff is a derivative/extension 
of [Between Meals](https://github.com/facebook/between-meals).

Chef Diff calculates changes for nodes, clients, users, environments, databags, roles, environment-specific roles and cookbooks between revisions in a Chef repo.

Chef Diff allows subdirs in nodes, clients and environments to enable the Chef repo layout to match a clustered multi Chef server infrastructure.

## Environment-specific roles (roles_local)

In addition to the standard `roles/` directory, Chef Diff supports a second
roles directory for environment-specific role overrides. By convention this
directory is called `roles_local/`, and subdirectories within it are part of
the role name — for example `roles_local/cluster/web.json` is reported as the
role `cluster/web`.

This is useful when running a multi-environment or multi-cluster Chef setup
where some roles differ per environment but you do not want to pollute the
shared `roles/` tree.

When using Chef Diff as a library, pass `role_local_dir` to `Changeset.new`:

```ruby
changeset = ChefDiff::Changeset.new(
  logger, repo, start_ref, end_ref,
  role_dir:       'roles',
  role_local_dir: 'roles_local',   # default used by chef-diff binary
  # … other dirs …
)
changeset.roles_local  # => array of ChefDiff::Changes::RoleLocal objects
```

The `chef-diff` binary uses `roles_local` as the default directory name and
reports changes under the heading `Roles_local changed:`.

## Usage

Cheff Diff is mainly intended to be used as a gem by other tools but provides a commandline inspection tool:

	$ chef-diff
	Usage: chef-diff [options] <repo_path>
	    -v, --verbose                    Run verbosely
	    -s, --start_ref REF              Git start reference
	    -e, --end_ref REF                Git end reference (default HEAD)

The logger passed to `Changeset.new` must be `::Logger`-compatible: `info` and
`debug` are called with a block that builds the message, so the string is only
made when that level is on. A logger whose `info(msg)` ignores blocks logs
`nil` instead.

## SVN support

Chef Diff includes an SVN backend (`ChefDiff::Repo::Svn`) inherited from
[Between Meals](https://github.com/facebook/between-meals). It is
**experimental** — its specs run against stubbed `svn` commands only, and it
has not been validated against a real SVN repository. Use at your own risk.

## Dependencies

* JSON
* Mixlib::ShellOut

## Testing

```sh
docker run --rm -v "$(pwd)":/app -w /app ruby:3.3 \
  sh -c "bundle install && bundle exec rake"
```
