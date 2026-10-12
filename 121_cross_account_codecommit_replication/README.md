# Cross-account CodeCommit replication

This project mirrors a source CodeCommit repository into a repository in a second AWS account while preserving commit IDs, history, dotfiles, branches, tags, deleted files, and deleted refs. The two account roots have independent Terraform state and never assume into the other account during Terraform execution.

## Apply

1. From `target_account`, load the secondary-account credentials, set `target_account_id` and `source_account_id`, then run `terraform apply`.
2. Pass the four values from `terraform output -json source_root_handoff` to the same-named source-root variables.
3. From `source_account`, load the primary-account credentials, set `source_account_id`, `target_account_id`, and `target_region`, then run `terraform apply`.
4. Wait for the first pipeline execution. Terraform creates the source repository's initial `main` commit before it creates CodePipeline, so the first Source action has a valid revision and mirrors it without a manual seed step.

The source apply needs AWS CLI on `PATH`. The AWS provider has no CodeCommit file/commit resource, and its `default_branch` argument can only select a branch that already exists, so a create-only `terraform_data` step calls CodeCommit `PutFile` with the same source-account credentials. It does nothing when `main` already exists; subsequent repository content belongs to Git rather than Terraform.

The source root also waits for the pipeline role policy to propagate before creating CodePipeline. The wait defaults to 30 seconds and can be raised with `pipeline_role_propagation_wait_seconds` if the account needs a longer IAM propagation margin.

The target root must exist first because its fixed role and repository are runtime prerequisites for the source build. Terraform cannot encode that edge across separate states, so both roots expose the order (rules.md I-4).

## How replication works

CodePipeline reacts only to creation or updates of the configured `main` branch and supplies the required source input artifact to CodeBuild. The build intentionally ignores that ZIP, clones the source repository with `git clone --mirror` while using the source build role, assumes the exact target role, and runs `git push --mirror` against an explicit target-region URL. Every triggered run therefore reconciles the complete ref set; a tag-only, non-main-branch-only, or ref-deletion-only change is mirrored on the next main update or manual pipeline run.

The target trust uses the always-existing source account root as its IAM principal and an `aws:PrincipalArn` condition for the exact future CodeBuild role. This lets the target root apply first without broadening who can assume the role (rules.md I-2).

## Workbench access

The workbench defaults to no inbound security-group rule. Run the `vscode_port_forward_command` output on a machine with the Session Manager plugin, then open the `vscode_url` (`http://localhost:8000` by default). Setting `allow_inbound_from_anywhere = true` exposes code-server without authentication and is appropriate only for a disposable, isolated demo.

## Destroy

Destroy `source_account` first so its pipeline and trusted CodeBuild role disappear, then destroy `target_account`. The artifact bucket uses `force_destroy`; destroying the source root permanently removes its pipeline artifacts.
