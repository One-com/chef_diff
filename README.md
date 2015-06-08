# Chef Diff

## Intro

Chef Diff is a library for calculating what Chef objects where modified 
between two revisions in a version control system. Chef Diff is a derivative/extension 
of [Between Meals](https://github.com/facebook/between-meals).

Chef Diff calculates changes for nodes, clients, users, environments, databags, roles and cookbooks between revisions in a Chef repo.

Chef Diff allows subdirs in nodes, clients and environments to enable the Chef repo layout to match a clustered multi Chef server infrastructure.

## Usage

Cheff Diff is mainly intended to be used as a gem by other tools but provides a commandline inspection tool:

	$ chef-diff
	Usage: chef-diff [options] <repo_path>
	    -v, --verbose                    Run verbosely
	    -s, --start_ref REF              Git start reference
	    -e, --end_ref REF                Git end reference (default HEAD)

## Dependencies

* JSON
* Mixlib::ShellOut
