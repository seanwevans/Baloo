# Security Policy

Baloo is a collection of Unix-style command-line utilities written in x86_64 assembly and linked without libc. Because these programs are intended to process files, paths, command-line arguments, environment variables, terminal input, and other untrusted local data, security reports are welcome even when an issue appears to affect only a single utility.

## Supported Versions

Baloo currently does not publish numbered stable releases. Security support applies to the default branch and to the most recent commit available from the project repository.

| Version or branch | Supported |
| --- | --- |
| Default branch | Yes |
| Historical commits, forks, or unmaintained branches | No |

If the project begins publishing formal releases, this table should be updated to identify supported release lines and any end-of-support dates.

## Reporting a Vulnerability

Please report suspected vulnerabilities privately before opening a public issue, pull request, discussion, or social media thread.

Preferred reporting channels, in order:

1. Use GitHub's private vulnerability reporting or Security Advisories feature for this repository, if available.
2. If private reporting is not available, contact the repository maintainer through a non-public channel associated with the GitHub project and include `Baloo security report` in the subject or first line.
3. If no private channel can be found, open a minimal public issue that says you have a potential security report and asks for a private contact path. Do not include exploit details in that public issue.

When reporting, include as much of the following information as possible:

- The affected utility or source file.
- The commit, branch, operating system, kernel version, assembler/linker versions, and exact build command used.
- The full command line needed to reproduce the issue.
- A minimal input file, environment, directory tree, or terminal setup that triggers the behavior.
- The expected result and the actual result.
- Any crash logs, register state, debugger output, syscall traces, sanitizer output, or core-file notes.
- A short impact assessment, such as denial of service, arbitrary file overwrite, information disclosure, privilege boundary concern, or unexpected command execution.
- Whether the issue is already public, known to affect another project, or has a deadline for coordinated disclosure.

Please do not send malicious binaries, weaponized payloads, or data copied from systems you do not own or have explicit permission to test. If a proof of concept is necessary, keep it minimal and safe.

## What to Expect

The maintainer will try to follow this process:

1. Acknowledge the report and confirm that it was received.
2. Reproduce and triage the issue.
3. Assign a severity based on exploitability, affected utilities, default behavior, and whether the issue crosses a meaningful privilege or trust boundary.
4. Develop and test a fix.
5. Coordinate disclosure timing with the reporter when practical.
6. Publish a public advisory, changelog entry, commit, or issue after users have a reasonable path to update.

Response times depend on maintainer availability. If you believe a report is being actively exploited or carries unusually high impact, say so clearly in the initial report.

## Disclosure Guidelines

Baloo asks reporters to use coordinated disclosure:

- Give the maintainer a reasonable opportunity to investigate and fix the issue before public disclosure.
- Avoid sharing exploit details publicly until a fix or mitigation is available.
- Keep communication factual and limited to the technical details needed to resolve the vulnerability.
- Notify the maintainer before publishing research, advisories, proof-of-concept code, or write-ups.

The project will not pursue action against security researchers who act in good faith, test only systems they own or are authorized to test, avoid privacy violations and service disruption, and give the project a reasonable chance to respond.

## Security Scope

Reports are especially useful for issues involving:

- Memory corruption, including stack corruption, buffer overflows, out-of-bounds reads or writes, use-after-free-like lifetime mistakes, and integer overflow that affects memory safety.
- Unsafe parsing of command-line arguments, file formats, text streams, binary streams, locale data, terminal control sequences, or environment variables.
- Incorrect handling of paths, symbolic links, hard links, special files, devices, FIFOs, sockets, mount points, or race-prone filesystem operations.
- Unexpected writes, truncation, deletion, permission changes, ownership changes, or metadata changes outside the user-requested target.
- Information disclosure from uninitialized memory, unintended file reads, terminal state leakage, process metadata, or environment handling.
- Privilege-boundary concerns, especially behavior that becomes dangerous when a Baloo utility is run by a privileged user, from automation, in a container, or against attacker-controlled paths.
- Command execution or process-control surprises in utilities that invoke, schedule, signal, or search for programs.
- Denial-of-service issues caused by infinite loops, unbounded allocation-like behavior, uncontrolled file growth, pathological CPU usage, stack exhaustion, or terminal lockups.
- Cryptographic or checksum implementation flaws that produce incorrect digests, unsafe verification behavior, or misleading success results.
- Build, test, or release-process weaknesses that could cause a user to build or run a different program than expected.

The following are usually out of scope unless they create a concrete security impact:

- Pure POSIX compatibility differences with no safety impact.
- Crashes that require intentionally invalid local input and cannot affect confidentiality, integrity, availability, or privilege boundaries.
- Missing features, documentation gaps, style issues, or performance concerns without a security consequence.
- Vulnerabilities that depend entirely on a compromised compiler, assembler, linker, kernel, shell, or test harness outside this repository.

## Threat Model and Assumptions

Baloo utilities are local command-line programs. They should treat command-line arguments, standard input, files, directories, environment variables, locale settings, terminal state, and process metadata as potentially untrusted.

Security expectations include:

- A utility should not read, write, delete, rename, chmod, chown, link, unlink, truncate, or create files beyond the behavior requested by its documented interface.
- A utility should fail safely when input is malformed, too large, unavailable, or changes during execution.
- A utility should avoid leaking memory contents or unrelated file contents in normal output, diagnostics, or exit behavior.
- A utility should preserve predictable exit statuses so scripts can make safe decisions.
- A utility should not assume that paths are stable, files are regular files, devices are benign, terminal output is trusted, or environment values are well formed.
- A utility should not rely on libc hardening because Baloo intentionally uses direct Linux syscalls and assembly-level implementations.

Baloo is not currently designed to be installed setuid or setgid. Do not grant elevated privileges to Baloo binaries unless the specific utility has been audited for that use.

## Hardening Recommendations for Users

Until a utility has been independently reviewed for a sensitive workload, consider these precautions:

- Run Baloo with the least privileges necessary.
- Avoid running Baloo binaries as root on attacker-controlled directories or files.
- Use temporary, disposable directories when testing unfamiliar inputs.
- Prefer containers, virtual machines, namespaces, seccomp, read-only mounts, or other sandboxing for untrusted data.
- Verify command lines and paths before using utilities that modify ownership, permissions, links, directories, or file contents.
- Keep build tools and the operating system updated.
- Rebuild from a trusted checkout and inspect local changes before installing binaries globally.

## Development Security Checklist

Contributors should consider the following before submitting changes:

- Validate argument counts, option parsing, numeric conversions, and pointer arithmetic.
- Check syscall return values and handle negative errno values consistently.
- Avoid fixed-size buffers unless every write is bounded and every length calculation is checked.
- Treat pathnames, environment variables, and file contents as attacker-controlled.
- Be careful with time-of-check/time-of-use races around filesystem metadata and path operations.
- Preserve file descriptors intentionally, and close descriptors that should not leak to child processes.
- Do not print uninitialized memory or buffers beyond their initialized length.
- Keep error paths simple and deterministic.
- Add regression tests for security-sensitive parsing, boundary conditions, and filesystem behavior when practical.
- Run formatting and test commands before requesting review.

## Preferred Fixes

Security fixes should be small, reviewable, and accompanied by tests or clear manual reproduction notes when feasible. A good fix usually includes:

- A minimal regression case or reproduction script.
- An explanation of the vulnerable code path.
- A description of the new bounds check, validation rule, syscall handling, or filesystem behavior.
- Confirmation that normal documented behavior still works.

Avoid mixing unrelated refactors or formatting-only changes into security fixes unless they are required to make the fix safe and understandable.

## Credits

Baloo is happy to credit reporters who want public acknowledgement. Please state how you would like to be credited when submitting a report. If you prefer not to be named, say so and the project will keep the public advisory anonymous.
