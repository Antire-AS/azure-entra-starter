# Group-based access control (optional).
#
# WHO CAN ACCESS THE APP?
#
#   By default, EVERYONE in your Entra ID tenant (your organization) can sign in
#   and use the chat. That means anyone with a @yourcompany.com account.
#
#   If that's fine for your use case, you don't need anything in this file.
#   Leave create_access_group = false and skip the rest.
#
#   If you want to restrict access to specific people, you create a security group
#   and add only the people who should have access. Everyone else in the org
#   will be blocked at the Microsoft login page — they never reach your app.
#
# HOW IS THIS ENFORCED?
#
#   Entra ID itself blocks non-members. The mechanism is:
#
#   1. The service principal (in auth.tf) has app_role_assignment_required = true.
#      This tells Entra ID: "only issue tokens to users who are assigned to this app."
#
#   2. The security group is assigned to the app (azuread_app_role_assignment below).
#      This tells Entra ID: "members of this group are allowed."
#
#   3. When a non-member tries to sign in, Entra ID shows error AADSTS50105:
#      "Your admin has configured the application to block users."
#      The user never reaches your app — they're stopped at Microsoft's login page.
#
#   No middleware, no token parsing, no backend code. Entra ID handles it.
#
# HOW TO ADD / REMOVE PEOPLE:
#
#   Portal:
#     Entra ID -> Groups -> <your group name> -> Members -> Add members / Remove
#
#   CLI:
#     az ad group member add \
#       --group "Chat App Users" \
#       --member-id $(az ad user show --id "user@yourcompany.com" --query id -o tsv)

# --- Variables ---

variable "create_access_group" {
  description = "Set to true to create a security group and restrict access to its members. When false (default), everyone in your organization can access the app."
  type        = bool
  default     = false
}

variable "access_group_name" {
  description = "Name of the security group to create (only used if create_access_group = true)."
  type        = string
  default     = "Chat App Users"
}

variable "access_group_members" {
  description = "List of user email addresses to add to the access group. You can also add members later via the Azure portal. Example: [\"alice@company.com\", \"bob@company.com\"]"
  type        = list(string)
  default     = []
}

# --- Security Group (optional) ---
# Only created if create_access_group = true.

resource "azuread_group" "access" {
  count = var.create_access_group ? 1 : 0

  display_name     = var.access_group_name
  description      = "Users allowed to access the ${var.project_name} chat application"
  security_enabled = true

  owners = [data.azuread_client_config.current.object_id]
}

# --- Assign the group to the app ---
resource "azuread_app_role_assignment" "group_access" {
  count = var.create_access_group ? 1 : 0

  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = azuread_group.access[0].object_id
  resource_object_id  = azuread_service_principal.main.object_id
}

# Look up user IDs from email addresses so we can add them as group members.
data "azuread_user" "members" {
  for_each            = var.create_access_group ? toset(var.access_group_members) : toset([])
  user_principal_name = each.value
}

# Add each user to the group.
resource "azuread_group_member" "members" {
  for_each = var.create_access_group ? data.azuread_user.members : {}

  group_object_id  = azuread_group.access[0].object_id
  member_object_id = each.value.object_id
}

# --- Output ---

output "access_group_id" {
  description = "The Object ID of the access group. Share this with admins who need to manage group membership."
  value       = var.create_access_group ? azuread_group.access[0].object_id : null
}
