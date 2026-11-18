# Contributing to Signal-iOS

Thank you for supporting Signal and looking for ways to help. Please review this document, as the conventions here may be different from what you're used to even if you've contributed to other open source projects before.

## Security issues

If you've found **and confirmed** a security vulnerability in Signal, please report it via email to security@signal.org instead of opening a GitHub Issue. Please see [SECURITY.md](SECURITY.md).

## Issues

If you're experiencing a bug in the Signal iOS client, you may open a GitHub Issue.

### Ensuring Issues are high quality

High-quality GitHub Issues help us understand and fix bugs more quickly. A high-quality Issue follows the checklist in the Issue template, and includes: a detailed description; repro steps; debug logs from all devices involved; screenshots or screen recordings; crash reports, if crashing.

Low-quality Issues lacking detail are difficult for us to resolve, and may be closed.

### Issues are for bugs, not feature requests

GitHub Issues should be used for bugs in the Signal iOS client, not feature requests. New ideas can be submitted and discussed on the [community forum](https://community.signalusers.org/c/feature-requests).

The ["Beta Feedback" category on the community forum](https://community.signalusers.org/c/beta-feedback/) is the best place to share beta feedback.

### Send support questions to support

You can reach support by sending an email to support@signal.org or by visiting the [Signal Support Center](https://support.signal.org/) where you can also search for existing troubleshooting articles and find answers to frequently asked questions. Please do not open GitHub Issues for support questions.

### Duplicate issues

Please search both open and closed issues to make sure your bug report is not a duplicate.

### GitHub is not a generic discussion forum

Conversations about open bug reports belong here. However, all other discussions should take place on the [community forum](https://community.signalusers.org). You can use the community forum to discuss anything that is related to Signal or to hang out with your fellow users in the "Off Topic" category.

### Open issues

We read every issue, but some bugs or features take priority over others. If the issue is open, we're tracking it!

## Pull requests

**A high-quality GitHub Issue is often more useful than a pull request.**

However, if you believe you've identified the root cause and fix for a bug, you may open a pull request.

**Please note that we do not generally accept changes that add new features, involve visual changes, or otherwise change the user experience.** We are a small team with a large roadmap of planned UX improvements, and each additional feature (developed internally or externally) adds an additional maintenance burden. The best changes fix bugs in our implementation of the existing user experience.

If you want to proceed with a pull request to fix a bug, please rigorously follow the Contributor Checklist in the pull request template, including:

- Make sure you can reproduce the issue your PR addresses on latest `main`.
    - **Important:** We cannot accept speculative fixes for non-reproducible issues.
- Make sure your contribution has been thoroughly tested, including testing existing behaviors to avoid regressions.
- Avoid changing existing UX.
- Make sure your commits are rebased onto the latest `main` branch.
- Make sure your commits are well-structured to make review easier.
- Make sure you sign the [CLA](https://signal.org/cla).

## How else can I contribute?

There are many ways to contribute that don't involve the code at all!

- Help new users learn about Signal. Talk about it with your friends and family: get them to join you in using it!
- Join the beta and test out recently-released features first.
- Try and reproduce or find workarounds for open issues, and leave comments, especially if you believe an open issue has been resolved.
- Test a given Signal-iOS behavior against [Signal-Android](https://github.com/signalapp/Signal-Android) and [Signal-Desktop](https://github.com/signalapp/Signal-Desktop), to see if their behavior matches.
- [Donate to Signal.](https://signal.org/donate/)

---

Signal is made for you. Thank you for your feedback and support. We're a small team, and it means the world to us.
