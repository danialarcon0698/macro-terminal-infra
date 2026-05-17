# ============================================================
# Cost allocation tags — Billing / Cost Explorer breakdown
# CE API is us-east-1 only; default provider region must match.
# Tag keys appear here after resources are tagged; activation can
# take up to 24h before Cost Explorer filters return data.
# ============================================================

resource "aws_ce_cost_allocation_tag" "project" {
  tag_key = "Project"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "environment" {
  tag_key = "Environment"
  status  = "Active"
}
