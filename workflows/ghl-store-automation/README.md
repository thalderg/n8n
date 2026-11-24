# GHL Store Automation

**Connect a Shopify store to GoHighLevel so every lead and customer moves through the sales pipeline on their own.**

A store owner loses sales in the gaps: a contact-form question that waits a day for an answer, a cart left at checkout, a customer who bought once and never came back. This system closes those gaps. Every store event becomes a GoHighLevel contact in the right pipeline stage, and the right message goes out at the right time: an instant reply to a new lead, a reminder for an abandoned cart, a win-back email to a customer who went quiet.

Built with n8n: 1 main workflow, 4 event handlers, 3 services, a contact form and a demo simulator; 4 n8n Data Tables.

> Tested end to end against a real Shopify development store and a real GoHighLevel sandbox. The names and emails in the images are test data.

---

## In 30 seconds

1. **One intake for everything.** Shopify webhooks, the shop's contact form and the daily schedule all enter one main workflow. It checks Shopify's signature and sends each event to its handler.
2. **Pipeline stages move on their own.** New Lead → Contacted → Cart Created → Purchased → Repeat Customer. A contact never moves backwards.
3. **The right message, once.** A lead gets a reply in seconds. An abandoned cart gets one reminder after 1 hour, never two. A customer quiet for 60 days gets a win-back email, then a follow-up 7 days later.
4. **Email always, SMS as an extra.** Every message goes by email; when the customer gave a phone number, an SMS goes too.
5. **Proof, not promises.** A Demo Simulator plays five customers against the real workflows and shows a PASS/FAIL table.

---

## What it looks like

| | |
|---|---|
| **The pipeline in GoHighLevel** | **The cart reminder email** |
| <img src="images/ghl-pipeline.png" alt="The Store Customers pipeline in GoHighLevel with contacts in each stage" width="400"> | <img src="images/email-cart-reminder.png" alt="The cart reminder email" width="400"> |
| **The Demo Simulator result** | **The contact form on the shop** |
| <img src="images/simulator-result.png" alt="The PASS/FAIL table of the Demo Simulator" width="400"> | <img src="images/shopify-contact-form.png" alt="The contact form embedded in the Shopify Contact page" width="400"> |

---

## The messages

Every template lives in a handler and is plain text you can change. `{offer}`, `{store_url}` and `{response_time}` come from the **Store Settings** node.

| When | Channel | Subject / text |
|---|---|---|
| A contact form arrives | Email | **Thanks for reaching out, {first_name}** · "…we received your message and will reply within {response_time}. In the meantime you can browse our store: {store_url}" |
| | SMS (if phone) | "Hi {first_name}, thanks for reaching out - we will reply within {response_time}." |
| A cart is still open after the wait | Email | **You left something in your cart** · "You left {cart_items} in your cart. Finish your order here: {recovery_url}" |
| | SMS (if phone) | "Hi {first_name}, you left {cart_items} in your cart. Finish your order here: {recovery_url}" |
| Last order 60 days ago | Email | **We miss you, {first_name}** · "It has been a while since your last order… {offer} Visit us: {store_url}" |
| 7 days later, still no order | Email | **A little something for you, {first_name}** · "We wanted to follow up: {offer}" |
| | SMS (if phone) | "Hi {first_name}, it's been a while! {offer} - {store_url}" |

In the GoHighLevel sandbox an SMS is not sent (a sandbox has no phone number): it is saved on the contact as a note "SMS (demo, not sent): …". With a GoHighLevel phone number, the send is one changed step in the GHL Adapter (Live).

---

## The big picture

```mermaid
flowchart TD
    SH["Shopify store<br/>checkouts + orders webhooks"] --> WF1
    CF["Store Contact Form<br/>embedded in the shop"] --> WF1
    SC["Daily schedule 09:00"] --> WF1
    SIM["Demo Simulator"] -->|signed test events| WF1
    WF1["WF1 · Store Events & Win-Back<br/>check, normalise, route"]
    WF1 --> H1["Handle Contact Form Lead"]
    WF1 --> H2["Handle Abandoned Cart"]
    WF1 --> H3["Handle Paid Order"]
    WF1 --> H4["Run Win-Back Campaign"]
    H1 & H2 & H3 & H4 --> ES["Email Sender"]
    H1 & H2 & H3 & H4 --> AD{"GHL adapter<br/>live or mock"}
    AD --> LIVE["GHL Adapter (Live)"] --> GHL[("GoHighLevel<br/>contacts, pipeline, tags, notes")]
    AD --> MOCK["GHL Adapter (Mock)"] --> MT[("Mock tables")]
    ES --> GM["Gmail"]
    ES --> MP["Mailpit<br/>test inbox"]
    H2 & H3 --> CK[("ghl_store_checkouts")]
    H3 & H4 --> CU[("ghl_store_customers")]
```

The main workflow only checks and routes. Each handler does one job and calls two services: the **Email Sender** (Gmail, Mailpit or both) and a **GHL adapter**. The adapter is chosen by one setting: **live** talks to GoHighLevel, **mock** writes the same actions into n8n Data Tables, so you can try the whole system with no GoHighLevel account.

---

## WF1: Store Events & Win-Back

The entry point. It runs on every webhook call to `/webhook/ghl-store-intake`, every day at 09:00 for the win-back, and by hand.

<p align="center"><img src="images/n8n-wf1-store-events-and-win-back.png" alt="WF1 in the n8n editor" width="760"></p>

```mermaid
flowchart TD
    A["Receive Store Event<br/>webhook"] --> S["Store Settings"]
    B["Daily Win-Back Schedule"] --> S
    C["Run Win-Back Manually"] --> S
    S --> D{"Event source?"}
    D -->|Shopify| SIG["Compute Shopify Signature<br/>HMAC with the store secret"]
    SIG --> V{"Signature valid?"}
    V -->|no| R1["Reject Invalid Shopify Signature P2"]
    D -->|admin win-back call| AT{"Admin token valid?"}
    AT -->|no| R2["Reject Unauthorized Admin Call P2"]
    V -->|yes| N["Normalise Event"]
    AT -->|yes| N
    D -->|contact form / schedule| N
    N --> P{"Can be processed?<br/>has an email, not ignored"}
    P -->|no| X["Drop Ignored Or Emailless Event"]
    P -->|yes| T{"Event type"}
    T -->|contact_form| H1["Handle Contact Form Lead"]
    T -->|checkout_created| H2["Handle Abandoned Cart"]
    T -->|order_paid| H3["Handle Paid Order"]
    T -->|winback_run| H4["Run Win-Back Campaign"]
```

- **Store Settings** holds every value you tune: cart wait, win-back days, email mode, store URL, offer text, reply time, sender address, admin token, the GoHighLevel IDs and which adapter to use.
- **Shopify events that count:** `checkouts/create`, `checkouts/update` while the checkout is not completed (Shopify adds the email only in an update), and `orders/paid`. Every other topic is dropped.
- **Normalise Event** turns every source into one shape: `event_type`, `email`, `phone`, `first_name`, `last_name`, `message`, `checkout_id`, `recovery_url`, `cart_items`, `cart_total`, `order_id`, `order_total`, `prior_order_count`. The name comes from what the customer typed at checkout (billing, then shipping address) before Shopify's saved customer. Phone numbers are cleaned to digits and a leading `+`.
- **Test copy rule:** on the n8n whose address contains `test_instance_host`, every event uses the mock adapter and Mailpit, whatever the settings say. You can point the store webhooks at a test copy and at production at the same time, and the test copy never writes to real customers.

## Handle Contact Form Lead

Called by WF1 for a `contact_form` event.

<p align="center"><img src="images/n8n-handler-contact-form-lead.png" alt="Handle Contact Form Lead in the n8n editor" width="760"></p>

```mermaid
flowchart TD
    A["Receive Handler Call"] --> B["Upsert Lead As New Lead<br/>tag source:contact-form"]
    B --> C["Send Lead Reply Email<br/>via Email Sender"]
    C --> D{"Reply sent?"}
    D -->|no| E["Lead Reply Not Sent<br/>stays New Lead"]
    D -->|yes| F{"Has phone?"}
    F -->|yes| G["Send Lead Reply SMS<br/>via GHL adapter"]
    F -->|no| H["Mark Lead As Contacted"]
    G --> H
```

- The contact is created or updated in GoHighLevel with the tag `source:contact-form`, in stage **New Lead**.
- It moves to **Contacted** only after the reply email went out.

## Handle Abandoned Cart

Called by WF1 for every `checkout_created` event. Shopify sends many events for one checkout (12 in one real test), so this handler acts once per checkout.

<p align="center"><img src="images/n8n-handler-abandoned-cart.png" alt="Handle Abandoned Cart in the n8n editor" width="760"></p>

```mermaid
flowchart TD
    A["Receive Handler Call"] --> B{"Checkout already tracked?"}
    B -->|yes| R["Refresh Stored Checkout Details<br/>newest phone, name, cart, link"]
    B -->|no| C["Claim Checkout Record<br/>at once, before the CRM call"]
    C --> D["Set Contact To Cart Created<br/>tag cart-open"]
    D --> E["Wait Before Cart Reminder<br/>1 hour"]
    E --> F["Get Checkout Record"]
    F --> G{"Still abandoned?"}
    G -->|"no: paid or already reminded"| X["Cart Converted Or Already Handled"]
    G -->|yes| H["Send Cart Reminder Email"]
    H --> I{"Has phone?"}
    I -->|yes| J["Send Cart Reminder SMS"]
    I -->|no| K["Mark Reminder Sent In Table"]
    J --> K
    K --> L["Tag Contact Reminder Sent<br/>cart-reminder-sent"]
```

- **Claim first:** the checkout row is written before the 2.5-second CRM call. Without this, two events a second apart both passed and two reminders went out.
- **Refresh, then remind:** later events of the same checkout only update the stored row. After the wait, the reminder reads that row, so a phone number typed last still gets the SMS.
- **One reminder only:** the row records `reminder_sent_at`, and a paid order sets `converted_at`. Either one stops the reminder.
- The contact moves to **Cart Created**, unless it is already Purchased or Repeat Customer.

## Handle Paid Order

Called by WF1 for an `orders/paid` event.

<p align="center"><img src="images/n8n-handler-paid-order.png" alt="Handle Paid Order in the n8n editor" width="760"></p>

```mermaid
flowchart TD
    A["Receive Handler Call"] --> B["Get Customer Record"]
    B --> C{"Earlier orders?"}
    C -->|none| D["Stage Purchased"]
    C -->|one or more| E["Stage Repeat Customer"]
    D & E --> F["Update Contact<br/>tag customer, remove cart-open, winback-active"]
    F -->|fails| P1["Order Sync Failed P1"]
    F --> G["Save Customer Order Data<br/>order count, last order date"]
    G --> H{"Order has checkout id?"}
    H -->|yes| I["Mark Checkout Converted<br/>stops the cart reminder"]
```

- A paid order is revenue, so a failed sync raises a **P1** alert (the highest).
- Saving the last order date is what the win-back reads later.

## Run Win-Back Campaign

Called by WF1 every day at 09:00, by hand, or by the Simulator.

<p align="center"><img src="images/n8n-handler-win-back-campaign.png" alt="Run Win-Back Campaign in the n8n editor" width="760"></p>

```mermaid
flowchart TD
    A["Receive Handler Call"] --> B{"Win-back enabled?"}
    B -->|no| X["Win-Back Disabled"]
    B -->|yes| C["Find Customers With Old Orders<br/>last order over 60 days ago"]
    B -->|yes| D["Find Customers Awaiting Follow-Up"]
    C --> E["Pick: not in a campaign,<br/>none finished in the last 180 days"]
    E --> F["Loop: send win-back email,<br/>tag winback-active"]
    D --> G["Pick: email sent 7+ days ago,<br/>no order since"]
    G --> H["Loop: send follow-up email,<br/>SMS if phone, tag winback-sms-sent"]
    F & H -->|one customer fails| P4["Win-Back Batch Failed P4<br/>the loop goes on"]
```

- Every customer is handled one by one: one failure does not stop the others.
- `winback_enabled` in Store Settings pauses the campaign without touching anything else.
- An order at any time moves the customer to Repeat Customer and clears `winback-active` (Handle Paid Order).

## Email Sender

A service every handler calls to send one email.

<p align="center"><img src="images/n8n-service-email-sender.png" alt="Email Sender in the n8n editor" width="760"></p>

```mermaid
flowchart LR
    A["Receive Email Request"] --> B{"Gmail mode?<br/>gmail or both"}
    B -->|yes| C["Send Email Via Gmail"]
    A --> D{"Mailpit mode?<br/>mailpit or both"}
    D -->|yes| E["Send Email Via Mailpit"]
    C & E --> F["Summarise Email Result"]
```

- `email_mode` in Store Settings: `gmail` (real delivery), `mailpit` (a local test inbox) or `both`.

## GHL Adapter (Live)

The service that talks to GoHighLevel. Every handler calls it with one action: `upsert_stage` (contact, tags, stage) or `send_sms`.

<p align="center"><img src="images/n8n-service-ghl-adapter-live.png" alt="GHL Adapter (Live) in the n8n editor" width="760"></p>

```mermaid
flowchart TD
    A["Receive Adapter Call"] --> B{"Action"}
    B -->|upsert_stage| C["Create Or Update GHL Contact"]
    C -->|fails| P2["GHL Contact Update Failed P2"]
    C --> D["Add / Remove Contact Tags<br/>GHL API"]
    D --> E["Find Opportunity For Contact"]
    E --> F{"Opportunity exists?"}
    F -->|no| G["Create GHL Opportunity"]
    F -->|yes, stage is later| H["Update GHL Opportunity Stage"]
    H -->|fails| P3["GHL Stage Move Failed P2"]
    B -->|send_sms| I["Find GHL Contact For SMS"]
    I --> J["Add SMS Note To Contact"]
```

- Contacts and opportunities use the native HighLevel node; tags, the opportunity search and notes use the GoHighLevel API with the same OAuth2 connection.
- **Never backwards:** the stage moves only forward in New Lead → Contacted → Cart Created → Purchased → Repeat Customer.

## GHL Adapter (Mock)

Same input and output as the live adapter, but it writes to two n8n Data Tables instead of GoHighLevel. Use it to try the system with no GoHighLevel account.

<p align="center"><img src="images/n8n-service-ghl-adapter-mock.png" alt="GHL Adapter (Mock) in the n8n editor" width="760"></p>

```mermaid
flowchart LR
    A["Receive Adapter Call"] --> B{"Action"}
    B -->|upsert_stage| C["Find Mock Contact"] --> D["Merge Tags And Decide Stage"] --> E["Save Mock Contact"] --> F["Log Mock Stage Change"]
    B -->|send_sms| G["Log Mock SMS"]
```

## Store Contact Form

A small n8n form you embed in the shop's Contact page. A visitor writes on the shop and becomes a lead.

<p align="center"><img src="images/n8n-utility-store-contact-form.png" alt="Store Contact Form in the n8n editor" width="760"></p>

```mermaid
flowchart LR
    A["Store Contact Form<br/>first name, last name, email, phone, message"] --> B["Send Contact Form To Store Workflow<br/>WF1 webhook"]
```

- In Shopify: **Online Store → Pages → Contact → Show HTML**, then paste `<iframe src="https://YOUR_N8N_HOST/form/store-contact" width="100%" height="760" style="border:0"></iframe>`.

## Demo Simulator

A test tool. It plays a customer against the real workflows, waits, then checks what really happened.

<p align="center"><img src="images/n8n-demo-simulator.png" alt="Demo Simulator in the n8n editor" width="760"></p>

```mermaid
flowchart TD
    A["Choose Customer Scenario<br/>form"] --> S["Simulator Settings"]
    B["Run All Scenarios"] --> S
    S --> C["Read Products (Shopify)<br/>Read GHL Pipelines"]
    C --> D["Prepare Scenario Runs"]
    D --> E{"Needs a dormant customer?"}
    E -->|yes| F["Seed Dormant Customer Row"]
    E & F --> G["Sign Event Body<br/>same HMAC as Shopify"]
    G --> H["Post Event To Store Workflow"]
    H --> I["Wait For Store Workflow<br/>150 s"]
    I --> J["Read results: Mailpit, GoHighLevel contact,<br/>opportunity, notes, mock log, Gmail"]
    J --> K["Assert Scenario Outcomes"]
    K --> L["Build Result Table"]
    L --> M["Delete Test Contact and Opportunity"]
```

| Scenario | What it sends | What must happen |
|---|---|---|
| Form filler | a contact form | stage Contacted, tag `source:contact-form`, reply email |
| Cart abandoner | a checkout, no order | stage Cart Created, reminder email (and SMS note with a phone), tag `cart-reminder-sent` |
| Buyer | a checkout, then its paid order | stage Purchased, **no** reminder |
| Repeat buyer | a paid order with an earlier order | stage Repeat Customer |
| Dormant customer | a customer row 61 days old, then a win-back run | win-back email, tag `winback-active` |

- It uses the store's first real product, signs each event like Shopify does, and deletes every GoHighLevel test contact and opportunity it created at the end.
- The demo cart wait is 2 minutes (so a person can finish a real checkout first); the Simulator checks after 150 seconds.

---

## Messages it sends on its own

| When | To whom | What |
|---|---|---|
| Seconds after a contact form | the lead | the reply email (and SMS) |
| 1 hour after a checkout, if not paid | the shopper | one cart reminder email (and SMS) |
| Every day at 09:00 | customers with a last order 60+ days ago | the win-back email |
| Every day at 09:00 | customers who got the win-back email 7+ days ago and did not order | the follow-up email (and SMS) |

---

## How it stays reliable

- **Signed events only.** Every Shopify call is checked with the store's HMAC secret. A bad signature stops with a **P2** alert. Admin calls (the win-back on demand) need the `x-admin-token` header.
- **Once per checkout.** The checkout is claimed in a table before anything slow happens; repeated Shopify events only refresh the row.
- **Never backwards.** A stage move to an earlier stage is refused.
- **Forced alert levels** for the central error handler: `Order Sync Failed P1`, `Reject Invalid Shopify Signature P2`, `GHL Contact Update Failed P2`, `GHL Stage Move Failed P2`, `Win-Back Batch Failed P4`.
- **Soft fails** on messages: if a reply email fails, the lead stays New Lead and the run goes on; one failed win-back customer does not stop the batch.
- **Sub-workflows are locked** to their callers, so nothing else can start a handler by mistake.
- Every workflow sends its errors to your error workflow (`YOUR_ERROR_WORKFLOW_ID`). The [Error Handling](../error-handling/) system in this repo is one you can use.

---

## Data

Four n8n Data Tables. Create them by hand in n8n (**Overview → Data tables → Create**) with the exact columns below, then put each table's ID in the nodes that use it.

**`ghl_store_checkouts`**: one row per Shopify checkout.

| Column | Type | What it holds |
|---|---|---|
| `checkout_id` | string | Shopify checkout token, links the checkout to its order |
| `email` | string | the shopper's email |
| `created_at` | date | first event of the checkout |
| `converted_at` | date | set when the order is paid |
| `reminder_sent_at` | date | set when the reminder went out |
| `phone` | string | newest phone number seen |
| `first_name`, `last_name` | string | newest name seen |
| `cart_items` | string | for example "Blue jacket x1" |
| `cart_total` | number | cart value |
| `recovery_url` | string | Shopify's link back to the checkout |

**`ghl_store_customers`**: one row per customer who ordered; the win-back reads it.

| Column | Type | What it holds |
|---|---|---|
| `email` | string | the customer's email |
| `ghl_contact_id` | string | the GoHighLevel contact |
| `first_name`, `last_name`, `phone` | string | contact details |
| `order_count` | number | paid orders so far |
| `last_order_date` | date | date of the last paid order |
| `winback_state` | string | empty, `email_sent` or `done` |
| `winback_started_at` | date | when the win-back email went out |
| `winback_last_completed` | date | when the last campaign finished (180-day cool-down) |

**`ghl_mock_contacts`** (mock adapter only): `email`, `contact_id`, `stage`, `tags` (all string).

**`ghl_mock_log`** (mock adapter only): `ts` (date), `run_id`, `kind`, `email`, `detail` (string): every contact, stage move and SMS the mock adapter recorded.

```mermaid
erDiagram
    ghl_store_checkouts }o--|| ghl_store_customers : "email"
    ghl_store_customers ||--o| GHL_CONTACT : "ghl_contact_id"
    ghl_mock_contacts ||--o{ ghl_mock_log : "email"
```

GoHighLevel holds the pipeline **Store Customers** with five stages in this order: New Lead, Contacted, Cart Created, Purchased, Repeat Customer. Create it by hand in GoHighLevel (**Opportunities → Pipelines**).

Tags used: `source:contact-form`, `cart-open`, `cart-reminder-sent`, `customer`, `winback-active`, `winback-sms-sent`.

---

## Setup

1. **Import** the 10 files (in n8n: **Workflows → Create workflow → ⋯ → Import from file**). Import the services first, then the handlers, then WF1, the form and the Simulator.
2. **Create the 4 Data Tables** above.
3. **Credentials**, one each:
   - **HighLevel OAuth2**, for the live adapter and the Simulator ([n8n docs](https://docs.n8n.io/integrations/builtin/credentials/highlevel/)). Not needed with the mock adapter.
   - **Crypto**, named *Shopify Webhook Signing Secret*, holding your store's webhook signing key (Shopify: **Settings → Notifications → Webhooks**).
   - **Gmail OAuth2**, for `email_mode` gmail or both ([n8n docs](https://docs.n8n.io/integrations/builtin/credentials/google/)).
   - **SMTP** to [Mailpit](https://mailpit.axllent.org/), for `email_mode` mailpit or both (host `mailpit` or `localhost`, port 1025, no login).
   - **Shopify OAuth2**, only for the Simulator ([n8n docs](https://docs.n8n.io/integrations/builtin/credentials/shopify/)).
4. **Connect the workflows.** Each handler calls services and WF1 calls handlers by workflow ID: open every *Execute Workflow* node and pick the right workflow from the list. In **Store Settings**, set `ghl_adapter_live_id`, `ghl_adapter_mock_id` and `email_sender_id` to the new IDs. In each sub-workflow's settings, set *This workflow can be called by* to its callers.
5. **Replace the placeholders:**

| Placeholder | Where | What to put there |
|---|---|---|
| `YOUR_GHL_LOCATION_ID` | WF1 Store Settings, Simulator Settings | your GoHighLevel sub-account (location) ID |
| `YOUR_GHL_PIPELINE_ID` | WF1 Store Settings | the Store Customers pipeline ID |
| `YOUR_GHL_STAGE_ID_NEW_LEAD` … `_REPEAT_CUSTOMER` | WF1 Store Settings | the ID of each of the 5 stages |
| `ADMIN_TOKEN` | WF1 Store Settings, Simulator Settings | a long random string, the same in both; while it stays `ADMIN_TOKEN`, admin calls are refused |
| `YOUR_TEST_N8N_HOST` | WF1 Store Settings | part of your test n8n's address, or leave it: then the settings always apply |
| `YOUR_CHECKOUTS_DATA_TABLE_ID`, `YOUR_CUSTOMERS_DATA_TABLE_ID`, `YOUR_MOCK_CONTACTS_DATA_TABLE_ID`, `YOUR_MOCK_LOG_DATA_TABLE_ID` | Data Table nodes | the table IDs (or pick the table from the list) |
| `YOUR_ERROR_WORKFLOW_ID` | every workflow's settings | your error workflow, or clear it |
| `YOUR_N8N_HOST` | Store Contact Form note | your n8n address, for the iframe |
| `REPLACE_WITH_YOUR_CREDENTIAL_ID` | credentialed nodes | select your credential in the node |

6. **Store Settings**: set `store_url`, `from_email`, `offer_text`, `response_time`, `email_mode`, and `adapter_config.mode` (`live` or `mock`). `cart_wait_seconds` is 120 for the demo; set 3600 for 1 hour.
7. **Shopify webhooks** (**Settings → Notifications → Webhooks**, format JSON): `Checkout creation`, `Checkout update` and `Order payment`, all to `https://YOUR_N8N_HOST/webhook/ghl-store-intake`.
8. **Publish** the services, then the handlers, then WF1 and the form.
9. **Test** with the Demo Simulator (**Run All Scenarios**) and check the PASS/FAIL table.

---

## Try it

| Do this | You should see |
|---|---|
| Send the contact form with your email | the reply email in seconds; the contact in **Contacted** with `source:contact-form` |
| Start a checkout on the shop, type an email, leave | after the wait, one reminder email; the contact in **Cart Created** with `cart-reminder-sent` |
| Same, but finish the payment | the contact in **Purchased**, no reminder |
| Pay a second order with the same email | the contact in **Repeat Customer** |
| Simulator: *Dormant customer* | the win-back email; tag `winback-active` |
| Simulator: *Run All Scenarios* | five PASS rows |

---

## Known limits

- SMS in a GoHighLevel sandbox is saved as a note, not sent. A real send needs a GoHighLevel phone number (and carrier registration in the US).
- Shopify's checkout refuses email domains that do not resolve (for example `example.test`); use a real domain for store tests.
- The win-back reads only customers this system has seen order. Older customers need a one-time import into `ghl_store_customers`.
- Only Shopify is supported as the store. Another platform needs a change in *Normalise Event* only.

## Files

| File | What it is |
|---|---|
| `wf1-store-events-and-win-back.json` | WF1: intake, checks, routing, win-back schedule |
| `handler-contact-form-lead.json` | Handle Contact Form Lead |
| `handler-abandoned-cart.json` | Handle Abandoned Cart |
| `handler-paid-order.json` | Handle Paid Order |
| `handler-win-back-campaign.json` | Run Win-Back Campaign |
| `service-email-sender.json` | Email Sender (Gmail, Mailpit or both) |
| `service-ghl-adapter-live.json` | GHL Adapter (Live): GoHighLevel |
| `service-ghl-adapter-mock.json` | GHL Adapter (Mock): n8n Data Tables |
| `utility-store-contact-form.json` | Store Contact Form, for the shop's Contact page |
| `demo-simulator.json` | Demo Simulator: five scenarios and a PASS/FAIL table |
| `images/` | screenshots |
| `LICENSE` | MIT License |

## License

[MIT](LICENSE). You may use, change and share these workflows, also for paid work. They come as is, with no warranty.
