---
id: ADR-MV8RUOYU
title: Lightroom-first keyboard shortcut conventions, with Apple Photos as an acceptable alternative
date: 2026-10-14T23:59:33.607Z
status: accepted
---

## Status
Accepted by the project owner on 2026-10-14.

## Context
Kromora's keyboard shortcuts should feel familiar to photographers moving from established photo editors. The current shortcut review identified delete, export, and Derive Look bindings that may conflict with common expectations.

## Decision
Use Adobe Lightroom as the preferred reference for shortcut conventions when Kromora has an equivalent action. Apple Photos is an acceptable reference too; when Lightroom has no clear equivalent or its convention does not fit Kromora's action, matching Apple Photos is a good choice. The owner expects Lightroom to be the more likely starting point for many users, so prefer it when both apps offer a clear equivalent.

This sets the reference hierarchy, not the exact key binding for every Kromora command. Select each binding during implementation after checking the target apps' current menus and preserving Kromora's command semantics and focus behavior.

## Consequences
Shortcut implementation and documentation should follow the Lightroom-first reference, with Apple Photos as an accepted fallback. This decision does not require full feature or workflow parity with either editor.
