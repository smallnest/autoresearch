#!/usr/bin/env python3
"""
Codeup CLI — Alibaba Cloud Codeup operations via SDK.

Replaces the GitLab-compatible REST API calls that don't work with Codeup.
Used by autoresearch's run.sh and run_all.sh in Codeup mode.

Environment variables:
  CODEUP_AK_ID      Alibaba Cloud Access Key ID (required)
  CODEUP_AK_SECRET  Alibaba Cloud Access Key Secret (required)
  CODEUP_ORG_ID     Codeup Organization ID (required)

Usage:
  python3 codeup_cli.py get_issue <workitem_identifier>
  python3 codeup_cli.py list_issues [--state=opened|closed|all] [--page=N] [--per-page=N]
  python3 codeup_cli.py create_mr <repo_id> <source_branch> <target_branch> <title> <description> [--create-from=API]
  python3 codeup_cli.py merge_mr <repo_id> <mr_iid>
  python3 codeup_cli.py get_mr <repo_id> <mr_iid>
  python3 codeup_cli.py list_mrs <repo_id> [--state=opened|closed|merged|all] [--page=N]
  python3 codeup_cli.py close_issue <workitem_identifier>
  python3 codeup_cli.py add_comment <workitem_identifier> <body>
  python3 codeup_cli.py get_workitem_status <workitem_identifier>
"""

import json
import os
import sys

from alibabacloud_devops20210625.client import Client
from alibabacloud_devops20210625 import models
from alibabacloud_tea_openapi import models as open_api_models


def get_client():
    """Create and return an authenticated Codeup SDK client."""
    ak_id = os.environ.get("CODEUP_AK_ID")
    ak_secret = os.environ.get("CODEUP_AK_SECRET")
    if not ak_id or not ak_secret:
        print(json.dumps({"error": "CODEUP_AK_ID and CODEUP_AK_SECRET required"}))
        sys.exit(1)

    config = open_api_models.Config(
        access_key_id=ak_id,
        access_key_secret=ak_secret,
        endpoint="devops.cn-hangzhou.aliyuncs.com",
    )
    return Client(config)


def get_org_id():
    org_id = os.environ.get("CODEUP_ORG_ID")
    if not org_id:
        print(json.dumps({"error": "CODEUP_ORG_ID required"}))
        sys.exit(1)
    return org_id


def resolve_workitem_id(client, org_id, identifier):
    """
    Resolve a work item identifier (like ISWB-8 or internal ID) to the
    form needed by the SDK. Both serial_number and internal identifier
    work directly with get_work_item_info.
    """
    return str(identifier)


def _resolve_internal_id(client, org_id, identifier):
    """
    Resolve to the internal workitem identifier needed by comment/status APIs.
    get_work_item_info works with both serial_number and internal ID,
    but comment/close APIs require the internal identifier.
    """
    try:
        response = client.get_work_item_info(org_id, str(identifier))
        return response.body.workitem.identifier
    except Exception:
        return str(identifier)


def cmd_get_issue(args):
    """Get work item info. Outputs JSON compatible with autoresearch."""
    if len(args) < 1:
        print(json.dumps({"error": "usage: get_issue <workitem_identifier>"}))
        sys.exit(1)

    client = get_client()
    org_id = get_org_id()
    workitem_id = resolve_workitem_id(client, org_id, args[0])

    try:
        response = client.get_work_item_info(org_id, workitem_id)
        wi = response.body.workitem

        # Map to GitLab Issue-like format for autoresearch compatibility
        result = {
            "title": wi.subject or "",
            "description": wi.document or "",
            "state": _map_status(wi.status, wi.logical_status),
            "labels": wi.tag or [],
            "serial_number": wi.serial_number or "",
            "identifier": wi.identifier or "",
            "category": wi.category_identifier or "",
            "assignee": wi.assigned_to or "",
            "created_at": wi.gmt_create,
            "updated_at": wi.gmt_modified,
        }
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


def cmd_list_issues(args):
    """List work items (mapped from Issues)."""
    client = get_client()
    org_id = get_org_id()

    state_filter = "opened"
    page = 1
    per_page = 20

    i = 0
    while i < len(args):
        if args[i] == "--state" and i + 1 < len(args):
            state_filter = args[i + 1]
            i += 2
        elif args[i].startswith("--state="):
            state_filter = args[i].split("=", 1)[1]
            i += 1
        elif args[i] == "--page" and i + 1 < len(args):
            page = int(args[i + 1])
            i += 2
        elif args[i].startswith("--page="):
            page = int(args[i].split("=", 1)[1])
            i += 1
        elif args[i] == "--per-page" and i + 1 < len(args):
            per_page = int(args[i + 1])
            i += 2
        elif args[i].startswith("--per-page="):
            per_page = int(args[i].split("=", 1)[1])
            i += 1
        else:
            i += 1

    # List across all categories
    all_items = []
    for cat in ["Task", "Bug", "Req"]:
        try:
            request = models.ListWorkitemsRequest(
                category=cat,
                page=page,
                page_size=per_page,
            )
            response = client.list_workitems(org_id, request)
            if response.body.workitems:
                all_items.extend(response.body.workitems)
        except Exception:
            pass

    # Filter by state
    results = []
    for wi in all_items:
        status = _map_status(wi.status, getattr(wi, "logical_status", None))
        if state_filter == "all" or status == state_filter:
            results.append({
                "iid": wi.serial_number or "",
                "identifier": wi.identifier or "",
                "title": wi.subject or "",
                "state": status,
                "labels": wi.tag if hasattr(wi, "tag") else [],
                "category": wi.category_identifier if hasattr(wi, "category_identifier") else "",
            })

    print(json.dumps(results, ensure_ascii=False))


def _map_status(status_name, logical_status):
    """Map Codeup workitem status to GitLab Issue state."""
    if logical_status:
        ls = logical_status.lower()
        if "closed" in ls or "done" in ls or "resolved" in ls:
            return "closed"
        if "open" in ls or "processing" in ls or "reopen" in ls:
            return "opened"
    if status_name:
        sn = status_name.lower()
        if "关闭" in sn or "完成" in sn or "已解决" in sn:
            return "closed"
        if "打开" in sn or "处理中" in sn or "待处理" in sn:
            return "opened"
    return "opened"


def cmd_create_mr(args):
    """Create a Merge Request.

    Note: Codeup API requires 'createFrom' field (since 2024+).
    Valid values: 'API', 'CLIENT', 'Web', etc.
    The API may return transient 500 errors; we retry up to 3 times.
    """
    if len(args) < 5:
        print(json.dumps({"error": "usage: create_mr <repo_id> <source_branch> <target_branch> <title> <description> [--create-from=API]"}))
        sys.exit(1)

    client = get_client()
    org_id = get_org_id()
    repo_id = args[0]
    source_branch = args[1]
    target_branch = args[2]
    title = args[3]
    description = args[4]

    # Parse optional --create-from flag
    create_from = "API"
    for i, a in enumerate(args):
        if a.startswith("--create-from="):
            create_from = a.split("=", 1)[1]

    # Retry logic for transient 500 errors
    import time
    max_retries = 3
    last_error = None
    for attempt in range(max_retries):
        if attempt > 0:
            time.sleep(2 * attempt)
        try:
            request = models.CreateMergeRequestRequest(
                organization_id=org_id,
                source_branch=source_branch,
                target_branch=target_branch,
                title=title,
                description=description,
                source_project_id=int(repo_id),
                target_project_id=int(repo_id),
                create_from=create_from,
            )
            response = client.create_merge_request(repo_id, request)
            mr = response.body.result
            result = {
                "iid": mr.local_id if hasattr(mr, "local_id") else None,
                "id": mr.id if hasattr(mr, "id") else None,
                "title": mr.title if hasattr(mr, "title") else title,
                "state": mr.state if hasattr(mr, "state") else "opened",
                "source_branch": source_branch,
                "target_branch": target_branch,
                "web_url": mr.web_url if hasattr(mr, "web_url") else "",
            }
            print(json.dumps(result, ensure_ascii=False))
            return
        except Exception as e:
            last_error = e
            err_str = str(e)
            # Only retry on 500/server errors, not on 400/client errors
            if "500" in err_str or "SYSTEM_UNKNOWN" in err_str:
                print(json.dumps({"warning": f"Attempt {attempt+1}/{max_retries} failed (server error), retrying..."}), file=sys.stderr)
                continue
            else:
                # Non-retryable error (400, 403, etc.)
                print(json.dumps({"error": str(e)}))
                sys.exit(1)
    # All retries exhausted
    print(json.dumps({"error": f"All {max_retries} attempts failed. Last error: {last_error}"}))
    sys.exit(1)


def cmd_merge_mr(args):
    """Merge a Merge Request."""
    if len(args) < 2:
        print(json.dumps({"error": "usage: merge_mr <repo_id> <mr_iid>"}))
        sys.exit(1)

    client = get_client()
    org_id = get_org_id()
    repo_id = args[0]
    mr_iid = args[1]

    try:
        request = models.MergeMergeRequestRequest(
            organization_id=org_id,
            merge_message=f"Merged by autoresearch",
            remove_source_branch=True,
        )
        response = client.merge_merge_request(repo_id, mr_iid, request)
        result = {
            "state": "merged",
            "iid": mr_iid,
            "success": response.body.success if hasattr(response.body, "success") else True,
        }
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


def cmd_get_mr(args):
    """Get MR info."""
    if len(args) < 2:
        print(json.dumps({"error": "usage: get_mr <repo_id> <mr_iid>"}))
        sys.exit(1)

    client = get_client()
    org_id = get_org_id()
    repo_id = args[0]
    mr_iid = args[1]

    try:
        request = models.GetMergeRequestRequest(organization_id=org_id)
        response = client.get_merge_request(repo_id, mr_iid, request)
        mr = response.body.result
        result = {
            "iid": mr.local_id if hasattr(mr, "local_id") else mr_iid,
            "title": mr.title if hasattr(mr, "title") else "",
            "state": mr.state if hasattr(mr, "state") else "",
            "source_branch": mr.source_branch if hasattr(mr, "source_branch") else "",
            "target_branch": mr.target_branch if hasattr(mr, "target_branch") else "",
            "web_url": mr.web_url if hasattr(mr, "web_url") else "",
        }
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


def cmd_list_mrs(args):
    """List Merge Requests."""
    if len(args) < 1:
        print(json.dumps({"error": "usage: list_mrs <repo_id> [--state=opened|merged|closed|all]"}))
        sys.exit(1)

    client = get_client()
    org_id = get_org_id()
    repo_id = args[0]
    state = "opened"

    i = 1
    while i < len(args):
        if args[i].startswith("--state="):
            state = args[i].split("=", 1)[1]
            i += 1
        elif args[i] == "--state" and i + 1 < len(args):
            state = args[i + 1]
            i += 2
        else:
            i += 1

    try:
        request = models.ListMergeRequestsRequest(
            organization_id=org_id,
            project_ids=repo_id,
            state=state,
            page=1,
            page_size=20,
        )
        response = client.list_merge_requests(request)
        results = []
        if hasattr(response.body, "result") and response.body.result:
            for mr in response.body.result:
                results.append({
                    "iid": mr.local_id if hasattr(mr, "local_id") else None,
                    "title": mr.title if hasattr(mr, "title") else "",
                    "state": mr.state if hasattr(mr, "state") else "",
                    "source_branch": mr.source_branch if hasattr(mr, "source_branch") else "",
                    "target_branch": mr.target_branch if hasattr(mr, "target_branch") else "",
                })
        print(json.dumps(results, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


def cmd_close_issue(args):
    """Close a work item (update status to closed)."""
    if len(args) < 1:
        print(json.dumps({"error": "usage: close_issue <workitem_identifier>"}))
        sys.exit(1)

    client = get_client()
    org_id = get_org_id()
    # Resolve to internal identifier (serial_number won't work for workflow APIs)
    workitem_id = _resolve_internal_id(client, org_id, args[0])

    try:
        # Get current workflow info to find the "close" action
        # First, get workitem info to find status
        wi_response = client.get_work_item_info(org_id, workitem_id)
        wi = wi_response.body.workitem

        # Get workflow to find close action
        wf_request = models.GetWorkItemWorkFlowInfoRequest()
        wf_response = client.get_work_item_work_flow_info(org_id, workitem_id, wf_request)

        # Find the close/resolve action
        close_action = None
        if wf_response.body.workflow and wf_response.body.workflow.workflow_actions:
            for action in wf_response.body.workflow.workflow_actions:
                action_name = (action.name or "").lower()
                if "关闭" in action_name or "close" in action_name or "完成" in action_name or "done" in action_name:
                    close_action = action
                    break

        if close_action:
            # Use the workflow action to transition
            # We need to use UpdateWorkitemField to trigger the action
            request = models.UpdateWorkitemFieldRequest(
                workitem_identifier=workitem_id,
                update_workitem_property_request=[
                    models.UpdateWorkitemFieldRequestUpdateWorkitemPropertyRequest(
                        field_identifier="status",
                        property_value=str(close_action.next_workflow_status_identifier),
                    )
                ],
            )
            client.update_workitem_field(org_id, request)
            print(json.dumps({"state": "closed", "identifier": workitem_id}))
        else:
            # Fallback: try to update status directly
            print(json.dumps({
                "warning": "Could not find close action in workflow",
                "current_status": wi.status,
                "identifier": workitem_id,
            }))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


def cmd_add_comment(args):
    """Add a comment to a work item."""
    if len(args) < 2:
        print(json.dumps({"error": "usage: add_comment <workitem_identifier> <body>"}))
        sys.exit(1)

    client = get_client()
    org_id = get_org_id()
    # Resolve to internal identifier (serial_number won't work for comment API)
    workitem_id = _resolve_internal_id(client, org_id, args[0])
    body = args[1]

    try:
        request = models.CreateWorkitemCommentRequest(
            workitem_identifier=workitem_id,
            content=body,
            format_type="RICHTEXT",
        )
        response = client.create_workitem_comment(org_id, request)
        result = {
            "success": response.body.success if hasattr(response.body, "success") else True,
            "identifier": workitem_id,
        }
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


def cmd_get_workitem_status(args):
    """Get just the status of a work item (lightweight check)."""
    if len(args) < 1:
        print(json.dumps({"error": "usage: get_workitem_status <workitem_identifier>"}))
        sys.exit(1)

    client = get_client()
    org_id = get_org_id()
    workitem_id = resolve_workitem_id(client, org_id, args[0])

    try:
        response = client.get_work_item_info(org_id, workitem_id)
        wi = response.body.workitem
        result = {
            "identifier": wi.identifier,
            "serial_number": wi.serial_number,
            "subject": wi.subject,
            "status": wi.status,
            "logical_status": wi.logical_status,
            "state": _map_status(wi.status, wi.logical_status),
        }
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


COMMANDS = {
    "get_issue": cmd_get_issue,
    "list_issues": cmd_list_issues,
    "create_mr": cmd_create_mr,
    "merge_mr": cmd_merge_mr,
    "get_mr": cmd_get_mr,
    "list_mrs": cmd_list_mrs,
    "close_issue": cmd_close_issue,
    "add_comment": cmd_add_comment,
    "get_workitem_status": cmd_get_workitem_status,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        print(__doc__)
        sys.exit(0)

    cmd = sys.argv[1]
    if cmd not in COMMANDS:
        print(json.dumps({"error": f"Unknown command: {cmd}. Available: {', '.join(COMMANDS)}"}))
        sys.exit(1)

    COMMANDS[cmd](sys.argv[2:])


if __name__ == "__main__":
    main()
