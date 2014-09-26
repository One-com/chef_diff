# Chef Diff

## Intro

Chef Diff is the library for calculating what Chef objects where modified 
between two revisions in a version control system. Chef Diff is a derivative/extension 
of Between Meals from Facebook.

Chef Diff calculates changes for nodes, clients, users, environments, databags, roles and cookbooks between revisions in a Chef repo.

Chef Diff allows subdirs in nodes, clients and environments to enable the Chef repo layout to match a clustered multi Chef server infrastructure.

## Dependencies

* Colorize
* JSON
* Mixlib::ShellOut
* Rugged
