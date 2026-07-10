<!--
Copyright (c) 2024, 2026, Oracle and/or its affiliates. All rights reserved.
The Universal Permissive License (UPL), Version 1.0 as shown at https://oss.oracle.com/licenses/upl/
-->

# FSTech Drive-Thru OCI Terraform stack

This stack deploys the full browser-based application:

- Autonomous AI Database 26ai with `ORDER_DETAILS` and `OFFERS`.
- 2,000 order-history rows and 25 offer rows, loaded idempotently. Repeated
  registration numbers provide realistic returning-customer histories.
- ORDS endpoints for history lookup, offer search, and order insertion.
- OCI Generative AI Agent, session-enabled endpoint, and six Terraform-managed
  function tools: `get_order_history`, `search_offers`, `get_weather`,
  `get_orders`, `insert_order`, and `vision_extract_registration_number`.
- OCI Vision-based vehicle registration recognition using the application's
  existing plate candidate selection (it does not substitute state text such
  as `TEXAS` for the registration).
- OCI Speech STT and TTS. Agent replies use the `Victoria` voice.
- A public web UI and FastAPI service on an Oracle Linux compute instance.
- A user-selected existing VCN/public subnet or a dedicated VCN created from
  user-supplied CIDRs, plus Object Storage, a dynamic group, and runtime IAM
  policy.

Each deployment receives a persisted six-character suffix for globally unique
ADB, bucket, Agent, and endpoint names. This prevents failed or parallel stacks
from colliding with names such as `FSTECHDB`.

## OCI compartment layout

The selected `compartment_ocid` is treated as a clean parent. Terraform creates
four child compartments and places resources by responsibility:

```text
Selected parent compartment
├── fstech-network      Created VCN resources or the app NSG for an existing VCN
├── fstech-data         Autonomous AI Database 26ai
├── fstech-ai           Generative AI Agent and endpoint
└── fstech-application  Compute runtime, Speech jobs, and Object Storage
```

The `fstech` prefix follows `name_prefix`, so separate environments can use
prefixes such as `fstdev`, `fsttest`, and `fstprod`. Runtime IAM statements
reference the exact AI and Application child-compartment OCIDs.

The deployment seed files are bundled at `runtime/seed/order_details.csv` and
`runtime/seed/offers.csv`. They are included automatically in every runtime
archive created by Terraform.

The runtime dynamic group matches instances in the dedicated Application
compartment. Terraform creates its policy and waits for IAM propagation before
creating the VM. Terraform is the only creator of remote function tools. At API
startup, a small reconciliation check removes legacy duplicate tools and
verifies that exactly the six Terraform-managed tools remain.

## Automatic IAM setup

For a zero-manual-IAM deployment in a new tenancy, run the Resource Manager
stack as a member of the tenancy `Administrators` group. Terraform then creates
the runtime dynamic group and every application policy automatically in
`iam.tf`.

If a non-administrator must deploy, an administrator must first authorize that
caller because Terraform cannot grant permission to itself before its first OCI
API operation. The optional least-practical deployment policy is documented in
[`iam/README.md`](iam/README.md).

## Resource Manager deployment (recommended)

1. Zip the contents of this `terraform` directory. Keep `runtime/`,
   `templates/`, and `schema.yaml` at the ZIP root.
2. In OCI, open **Resource Manager > Stacks**, create a stack from the ZIP, and
   choose the clean parent compartment under which the four application
   compartments should be created.
3. Select Terraform 1.5.x (OCI currently uses CLI 1.5.7).
4. Choose whether to use an existing network or create a dedicated network:
   - For an existing network, select its compartment, VCN, and public subnet
     from the Resource Manager lists. The subnet must permit public IPs and
     route `0.0.0.0/0` through an Internet Gateway.
   - For a new network, enter the VCN and public-subnet CIDRs. No CIDR is
     embedded in the stack. Use non-overlapping ranges if future VCN peering is
     planned.
5. Confirm the tenancy and compartment values, then run **Plan** and **Apply**.
6. Open the `application_url` output. Cloud-init normally needs 10-20 minutes
   after the instance becomes RUNNING.

Resource Manager supplies its own OCI provider authentication and current
region. Thus, the normal stack form only needs tenancy/compartment placement.
The applying principal must either be a tenancy administrator or have the
optional deployment policy documented above.

Use a deployment region where Generative AI Agents, Autonomous AI Database
26ai, Vision, and Speech STT/TTS with the Victoria voice are all available.
All application and AI-service calls use the Resource Manager stack region;
there is no embedded Chicago or Phoenix runtime region.

Compartments, dynamic groups, and policies are sent through the aliased
`oci.home` provider because OCI permits IAM CREATE, UPDATE, and DELETE calls
only in the tenancy home region. The stack discovers that region from
`oci_identity_region_subscriptions`; it is not a user input.

### Network selection and CIDR behavior

Selecting an existing VCN grants Terraform permission to inspect that VCN and
subnet and create the application NSG/VNIC attachment. The stack does not edit
the existing subnet's route table or security lists. It validates that the
subnet belongs to the chosen VCN and allows public IPs; the user remains
responsible for selecting a subnet whose route table reaches an Internet
Gateway.

Selecting a new VCN creates the VCN, Internet Gateway, public route table,
public subnet, and application NSG. The VCN and subnet CIDRs are required stack
inputs and have no defaults. OCI allows separate VCNs to have overlapping
CIDRs, but such overlap complicates or prevents peering and transitive routing,
so choose ranges according to the tenancy's network plan.

### Existing GenAI Agent quota

If Plan or Apply reports `LimitExceeded: agent-count`, either delete an unused
Agent/request a service-limit increase, or reuse an existing endpoint:

1. Set `create_genai_agent` to `false`.
2. Set `existing_agent_id` to the parent Agent OCID.
3. Set `existing_agent_endpoint_id` to the endpoint OCID.
4. Set `existing_agent_compartment_ocid` to the compartment containing it.

Terraform will skip Agent creation, attach the six function tools to the
supplied parent Agent, and grant the runtime dynamic group access to its
compartment.

Terraform creates the private Object Storage bucket first, then uploads the ADB
wallet object, and finally uploads the runtime object. These are direct resource
dependencies; no arbitrary Object Storage sleep is used. A failed bucket create
therefore prevents either upload from starting. GenAI function tools remain
serialized because their control plane requires stabilization between creates.

## Local Terraform deployment

Local execution also requires an OCI API-key profile and an explicit region:

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Edit `terraform.tfvars` with the two OCIDs. The example selects `APIKey` auth
and uses the `DEFAULT` profile from `~/.oci/config`.

## First-boot behavior

The instance downloads the versioned application bundle, opens the generated
ADB wallet, connects as the automatically provisioned `ADMIN` account, merges
both CSV files into `ADMIN.ORDER_DETAILS` and `ADMIN.OFFERS`, and defines the
ORDS routes before starting the API. No intermediate database user or manual
database step is required. Initialization is idempotent and verifies at least
2,000 order rows and 25 offer rows before the API is allowed to start. Systemd
restarts the API if OCI IAM propagation is not complete on its first attempt.
The UI service also installs its required runtime CLI and rebuilds automatically
if cloud-init did not finish the initial frontend build. No SSH or Database
Actions step is part of a normal deployment.

The runtime is UI-only. Browser text, image, STT, and TTS requests enter through
FastAPI behind Nginx.

Terraform/Resource Manager reports infrastructure creation separately from
cloud-init. After Apply succeeds, open the `bootstrap_health_url` output. A
complete deployment returns JSON containing `"database":"ready"`,
`"schema":"ADMIN"`, `"order_rows":2000` (or more), and
`"offer_rows":25` (or more). During first boot the URL can remain unavailable
for 10-20 minutes.

The expected ORDS module is `drive_thru`, owned by `ADMIN` and published below
the `/ords/admin/api/` base path. It is visible in the standard ADMIN Database
Actions REST dashboard. Use the `database_verification_sql` stack output in the
ADMIN SQL worksheet to verify the seed counts.

The module publishes four explicitly named REST APIs:

- `GET /ords/admin/api/get_order_history?registration_number=NCK6686`
- `GET /ords/admin/api/search_offers?registration_number=NCK6686`
- `GET /ords/admin/api/get_orders`
- `POST /ords/admin/api/insert_order`

Their complete deployment-specific URLs are returned by the `ords_rest_apis`
Terraform output.

If an SSH key was supplied, the `bootstrap_status_command` output gives a
diagnostic command. Otherwise use the OCI serial console or cloud-init logs.

## VM installation and file layout

The VM is disposable application infrastructure. Terraform renders
`templates/cloud-init.yaml.tftpl` into instance user data, and Oracle Linux
cloud-init performs the complete installation without an interactive SSH or
Database Actions step.

Cloud-init installs these operating-system packages:

- Python 3.11, `pip`, and the Python virtual-environment tooling.
- Nginx, `unzip`, `xz`, and SELinux/firewall support tools.
- Node.js 22.14.0 and npm from the official Node.js binary distribution.

The resulting file layout is:

```text
/opt/fstech/
├── app/                    Extracted application runtime
│   ├── web_api.py          FastAPI text, image, STT, and TTS bridge
│   ├── agent-codex-working.py
│   ├── agent_init.py       GenAI tool reconciliation and verification
│   ├── db_init.py          Tables, CSV seed data, and ORDS setup
│   ├── seed/               Bundled order_details.csv and offers.csv
│   ├── ui/                 Next.js browser application
│   ├── start-backend.sh
│   └── start-ui.sh
├── venv/                   Python virtual environment and dependencies
├── wallet/                 Extracted ADB client wallet
├── runtime.zip             Downloaded application bundle
└── wallet.zip              Downloaded wallet archive

/etc/fstech.env             Generated runtime configuration (mode 0600)
/etc/systemd/system/fstech-api.service
/etc/systemd/system/fstech-ui.service
/etc/nginx/conf.d/fstech.conf
```

`/etc/fstech.env` contains generated endpoints and database credentials and
must not be printed, copied into tickets, or committed. Its mode is `0600`, and
it is readable only by the `fstech` service account and root. The API startup
script loads it into the process. The ADB wallet password and ADMIN password
are generated by Terraform and are also present as sensitive values in
Resource Manager state.

The installation sequence is:

1. Install OS packages, Node.js, and npm.
2. Create the non-login `fstech` service account and `/opt/fstech` folders.
3. Download the runtime and ADB wallet through temporary Object Storage
   pre-authenticated URLs generated by Terraform.
4. Create `/opt/fstech/venv` and install `runtime/requirements.txt`.
5. Run `npm ci` and build the Next.js UI.
6. Configure SELinux, the host firewall, Nginx, and systemd.
7. Start the API, UI, and Nginx services.

At every API start, `start-backend.sh` retries `db_init.py` until the ADB,
tables, seed rows, and ORDS handlers are ready. It then retries
`agent_init.py` until the six GenAI function tools are reconciled, and finally
starts Uvicorn. This is why systemd can temporarily show the API service as
running while port 8000 is not listening during initial database or agent
setup.

## Services, ports, and request flow

Only TCP port 80 is opened publicly. Nginx is the public entry point and routes
requests internally:

```text
Browser :80 -> Nginx
             ├── / and UI assets -> Next.js 127.0.0.1:3000
             ├── /api/*           -> FastAPI 127.0.0.1:8000
             └── /health          -> FastAPI 127.0.0.1:8000/health
```

The relevant services are:

- `fstech-api.service`: initializes ADB/ORDS and GenAI tools, then runs FastAPI.
- `fstech-ui.service`: verifies/builds the UI if needed, then runs Next.js.
- `nginx.service`: publishes the unified application on port 80.

## Instance diagnostics

If bootstrap is still running or the health check is unavailable, use these
read-only commands on the instance:

```bash
sudo cloud-init status --long
sudo tail -n 300 /var/log/cloud-init-output.log

sudo systemctl status fstech-api.service --no-pager -l
sudo systemctl status fstech-ui.service --no-pager -l
sudo systemctl status nginx.service --no-pager -l

sudo journalctl -u fstech-api.service -n 300 --no-pager -l
sudo journalctl -u fstech-ui.service -n 300 --no-pager -l
sudo journalctl -u nginx.service -n 100 --no-pager -l

sudo ss -lntp
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:3000/
curl --fail http://127.0.0.1/health
```

Application files can be inspected with `sudo ls -la /opt/fstech/app`, and the
generated services with `sudo systemctl cat fstech-api.service` and
`sudo systemctl cat fstech-ui.service`. Do not display `/etc/fstech.env`
because it contains secrets.

## Applying application updates

Upload the new stack ZIP, update the existing Resource Manager stack, run
**Plan**, and then run **Apply**. Terraform versions the runtime Object Storage
object and replaces the disposable application VM whenever that bundle
changes. Cloud-init therefore repeats the installation and database/agent
reconciliation against the existing ADB. Seed loading and ORDS creation are
idempotent, so no manual copying or package installation is expected.

After Apply, wait for `bootstrap_health_url` to report readiness before using
`application_url`. Replacing the VM changes its public IP unless a reserved IP
or load balancer is added outside this demo stack.

## Security and production notes

- The generated database credentials are marked sensitive by their resources
  but remain in Terraform state. Store state in OCI Resource Manager or another
  protected backend.
- Using `ADMIN` for application tables and public ORDS routes provides the
  requested zero-touch deployment, but it has a larger security blast radius
  than a dedicated least-privilege schema. For a production deployment, move
  these objects back to an application schema and store its credential in OCI
  Vault.
- Port 80 is public so the demo is immediately reachable. Add TLS, a load
  balancer/WAF, and authentication before production use.
- The four demo ORDS routes are public. Add ORDS OAuth/roles before exposing
  customer or order data in production.
- Destroying the stack deletes the database and seeded data unless OCI deletion
  protection or backups are added first.
