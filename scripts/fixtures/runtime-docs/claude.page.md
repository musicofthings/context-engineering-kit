<!-- FIXTURE: trimmed excerpt of Claude Code hooks reference, captured 2026-10-19.
     Test data for scripts/eval_doc_drift.py. Heading depths, table
     separators and code fences are faithful to the live page; prose and
     payload-schema tables are cut. Not documentation — do not read as
     instructions.

     Named <runtime>.page.md, never <runtime>.md: a fixture called
     claude.md is picked up by Claude Code's own CLAUDE.md discovery on a
     case-insensitive filesystem, which would load a page of untrusted
     fetched vendor text as project instructions. -->

Source: https://code.claude.com/docs/en/hooks

## Hook events

### SessionStart

#### SessionStart input

#### SessionStart decision control

#### Reload skills that a hook installs

#### Persist environment variables

```bash theme={null}
#!/bin/bash

ENV_BEFORE=$(export -p | sort)

# Run your setup commands that modify the environment
source ~/.nvm/nvm.sh
nvm use 20

if [ -n "$CLAUDE_ENV_FILE" ]; then
  ENV_AFTER=$(export -p | sort)
  comm -13 <(echo "$ENV_BEFORE") <(echo "$ENV_AFTER") >> "$CLAUDE_ENV_FILE"
fi

exit 0
```

### Setup

#### Setup input

#### Setup decision control

### InstructionsLoaded

#### InstructionsLoaded input

#### InstructionsLoaded decision control

### UserPromptSubmit

#### UserPromptSubmit input

#### UserPromptSubmit decision control

#### What a blocked prompt leaves behind

### UserPromptExpansion

#### UserPromptExpansion input

#### UserPromptExpansion decision control

### MessageDisplay

#### MessageDisplay input

#### MessageDisplay output

### PreToolUse

#### PreToolUse input

#### PreToolUse decision control

#### Defer a tool call for later

### PermissionRequest

#### PermissionRequest input

#### PermissionRequest decision control

#### Permission update entries

### PostToolUse

#### PostToolUse input

#### PostToolUse decision control

#### Annotate a result for the auto mode classifier

### PostToolUseFailure

#### PostToolUseFailure input

#### PostToolUseFailure decision control

### PostToolBatch

#### PostToolBatch input

#### PostToolBatch decision control

### PermissionDenied

#### PermissionDenied input

#### PermissionDenied decision control

### Notification

#### Notification input

### SubagentStart

#### SubagentStart input

### SubagentStop

#### SubagentStop input

### TaskCreated

#### TaskCreated input

#### TaskCreated decision control

### TaskCompleted

#### TaskCompleted input

#### TaskCompleted decision control

```bash theme={null}
#!/bin/bash
INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject')

# Run the test suite
if ! npm test 2>&1; then
  echo "Tests not passing. Fix failing tests before completing: $TASK_SUBJECT" >&2
  exit 2
fi

exit 0
```

### Stop

#### Stop input

#### Stop decision control

### StopFailure

#### StopFailure input

### TeammateIdle

#### TeammateIdle input

#### TeammateIdle decision control

### ConfigChange

#### ConfigChange input

#### ConfigChange decision control

### CwdChanged

#### CwdChanged input

#### CwdChanged output

### DirectoryAdded

#### DirectoryAdded input

### FileChanged

#### FileChanged input

#### FileChanged output

### WorktreeCreate

#### WorktreeCreate input

#### WorktreeCreate output

### WorktreeRemove

#### WorktreeRemove input

### PreCompact

#### PreCompact input

### PostCompact

#### PostCompact input

### PreModelSwitch

#### PreModelSwitch input

#### PreModelSwitch decision control

#### PreModelSwitch timeouts and other exit codes

### PostModelSwitch

#### PostModelSwitch input

#### PostModelSwitch decision control

### SessionEnd

#### SessionEnd input

### Elicitation

#### Elicitation input

#### Elicitation output

#### Other ways to decline an elicitation

#### Answer a form request from a script

### ElicitationResult

#### ElicitationResult input

#### ElicitationResult output
