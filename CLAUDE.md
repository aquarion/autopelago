# autopelago

## Ansible

- Never run `ansible-playbook` piped through `tail`, `head`, or anything else that truncates output. Redirect full output to a file (e.g. `poetry run ansible-playbook ... 2>&1 | tee /tmp/run.log`) so the complete task list, including every `changed:` line, is preserved for review. Playbook runs are not always safely repeatable to recover lost output — once a task changes state, rerunning shows `ok`, not `changed`.
