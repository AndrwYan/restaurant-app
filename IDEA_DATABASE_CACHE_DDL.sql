-- Reconstructed from IntelliJ IDEA database cache:
-- .idea/dataSources/953eaa8e-b595-4a20-86b8-a3d854b6ac1f.xml
-- .idea/dataSources/953eaa8e-b595-4a20-86b8-a3d854b6ac1f/storage_v2/_src_/database/postgres.edMnLQ/schema/*.zip
--
-- Cached data source:
--   name: postgres@localhost
--   url: jdbc:postgresql://localhost:5432/postgres
--   user: postgres
--   product: PostgreSQL 16.0

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DROP SCHEMA IF EXISTS customer CASCADE;
DROP SCHEMA IF EXISTS "order" CASCADE;
DROP SCHEMA IF EXISTS payment CASCADE;
DROP SCHEMA IF EXISTS restaurant CASCADE;

CREATE SCHEMA customer;
CREATE SCHEMA "order";
CREATE SCHEMA payment;
CREATE SCHEMA restaurant;

CREATE TYPE approval_status AS ENUM ('APPROVED', 'REJECTED');
CREATE TYPE order_status AS ENUM ('PENDING', 'PAID', 'APPROVED', 'CANCELLED', 'CANCELLING');
CREATE TYPE outbox_status AS ENUM ('STARTED', 'COMPLETED', 'FAILED');
CREATE TYPE payment_status AS ENUM ('COMPLETED', 'CANCELLED', 'FAILED');
CREATE TYPE saga_status AS ENUM ('STARTED', 'FAILED', 'SUCCEEDED', 'PROCESSING', 'COMPENSATING', 'COMPENSATED');
CREATE TYPE transaction_type AS ENUM ('DEBIT', 'CREDIT');

CREATE TABLE customer.customers
(
    id uuid NOT NULL,
    username varchar NOT NULL,
    first_name varchar NOT NULL,
    last_name varchar NOT NULL,
    CONSTRAINT customers_pkey PRIMARY KEY (id)
);

CREATE MATERIALIZED VIEW customer.order_customer_m_view AS
SELECT id,
       username,
       first_name,
       last_name
FROM customer.customers;

CREATE FUNCTION customer.refresh_order_customer_m_view() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    refresh materialized VIEW customer.order_customer_m_view;
    return null;
END;
$$;

CREATE TRIGGER refresh_order_customer_m_view
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON customer.customers
    FOR EACH STATEMENT
EXECUTE PROCEDURE customer.refresh_order_customer_m_view();

CREATE TABLE "order".customers
(
    id uuid NOT NULL,
    username varchar NOT NULL,
    first_name varchar NOT NULL,
    last_name varchar NOT NULL,
    CONSTRAINT customers_pkey PRIMARY KEY (id)
);

CREATE TABLE "order".orders
(
    id uuid NOT NULL,
    customer_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    tracking_id uuid NOT NULL,
    price numeric(10, 2) NOT NULL,
    order_status order_status NOT NULL,
    failure_messages varchar,
    CONSTRAINT orders_pkey PRIMARY KEY (id)
);

CREATE TABLE "order".order_address
(
    id uuid NOT NULL,
    order_id uuid NOT NULL,
    street varchar NOT NULL,
    postal_code varchar NOT NULL,
    city varchar NOT NULL,
    CONSTRAINT order_address_pkey PRIMARY KEY (id, order_id),
    CONSTRAINT order_address_order_id_key UNIQUE (order_id),
    CONSTRAINT "FK_ORDER_ID" FOREIGN KEY (order_id)
        REFERENCES "order".orders (id)
        ON DELETE CASCADE
);

CREATE TABLE "order".order_items
(
    id bigint NOT NULL,
    order_id uuid NOT NULL,
    product_id uuid NOT NULL,
    price numeric(10, 2) NOT NULL,
    quantity integer NOT NULL,
    sub_total numeric(10, 2) NOT NULL,
    CONSTRAINT order_items_pkey PRIMARY KEY (id, order_id),
    CONSTRAINT "FK_ORDER_ID" FOREIGN KEY (order_id)
        REFERENCES "order".orders (id)
        ON DELETE CASCADE
);

CREATE TABLE "order".payment_outbox
(
    id uuid NOT NULL,
    saga_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    processed_at timestamp with time zone,
    type varchar NOT NULL,
    payload jsonb NOT NULL,
    outbox_status outbox_status NOT NULL,
    saga_status saga_status NOT NULL,
    order_status order_status NOT NULL,
    version integer NOT NULL,
    CONSTRAINT payment_outbox_pkey PRIMARY KEY (id)
);

CREATE INDEX payment_outbox_saga_status
    ON "order".payment_outbox (type, outbox_status, saga_status);

CREATE TABLE "order".restaurant_approval_outbox
(
    id uuid NOT NULL,
    saga_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    processed_at timestamp with time zone,
    type varchar NOT NULL,
    payload jsonb NOT NULL,
    outbox_status outbox_status NOT NULL,
    saga_status saga_status NOT NULL,
    order_status order_status NOT NULL,
    version integer NOT NULL,
    CONSTRAINT restaurant_approval_outbox_pkey PRIMARY KEY (id)
);

CREATE INDEX restaurant_approval_outbox_saga_status
    ON "order".restaurant_approval_outbox (type, outbox_status, saga_status);

CREATE TABLE payment.credit_entry
(
    id uuid NOT NULL,
    customer_id uuid NOT NULL,
    total_credit_amount numeric(10, 2) NOT NULL,
    CONSTRAINT credit_entry_pkey PRIMARY KEY (id)
);

CREATE TABLE payment.credit_history
(
    id uuid NOT NULL,
    customer_id uuid NOT NULL,
    amount numeric(10, 2) NOT NULL,
    type transaction_type NOT NULL,
    CONSTRAINT credit_history_pkey PRIMARY KEY (id)
);

CREATE TABLE payment.payments
(
    id uuid NOT NULL,
    customer_id uuid NOT NULL,
    order_id uuid NOT NULL,
    price numeric(10, 2) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    status payment_status NOT NULL,
    CONSTRAINT payments_pkey PRIMARY KEY (id)
);

CREATE TABLE payment.order_outbox
(
    id uuid NOT NULL,
    saga_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    processed_at timestamp with time zone,
    type varchar NOT NULL,
    payload jsonb NOT NULL,
    outbox_status outbox_status NOT NULL,
    payment_status payment_status NOT NULL,
    version integer NOT NULL,
    CONSTRAINT order_outbox_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX payment_order_outbox_saga_id_payment_status_outbox_status
    ON payment.order_outbox (type, saga_id, payment_status, outbox_status);

CREATE INDEX payment_order_outbox_saga_status
    ON payment.order_outbox (type, payment_status);

CREATE TABLE restaurant.restaurants
(
    id uuid NOT NULL,
    name varchar NOT NULL,
    active boolean NOT NULL,
    CONSTRAINT restaurants_pkey PRIMARY KEY (id)
);

CREATE TABLE restaurant.products
(
    id uuid NOT NULL,
    name varchar NOT NULL,
    price numeric(10, 2) NOT NULL,
    available boolean NOT NULL,
    CONSTRAINT products_pkey PRIMARY KEY (id)
);

CREATE TABLE restaurant.restaurant_products
(
    id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    CONSTRAINT restaurant_products_pkey PRIMARY KEY (id),
    CONSTRAINT "FK_RESTAURANT_ID" FOREIGN KEY (restaurant_id)
        REFERENCES restaurant.restaurants (id)
        ON DELETE RESTRICT,
    CONSTRAINT "FK_PRODUCT_ID" FOREIGN KEY (product_id)
        REFERENCES restaurant.products (id)
        ON DELETE RESTRICT
);

CREATE TABLE restaurant.order_approval
(
    id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    order_id uuid NOT NULL,
    status approval_status NOT NULL,
    CONSTRAINT order_approval_pkey PRIMARY KEY (id)
);

CREATE TABLE restaurant.order_outbox
(
    id uuid NOT NULL,
    saga_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    processed_at timestamp with time zone,
    type varchar NOT NULL,
    payload jsonb NOT NULL,
    outbox_status outbox_status NOT NULL,
    approval_status approval_status NOT NULL,
    version integer NOT NULL,
    CONSTRAINT order_outbox_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX restaurant_order_outbox_saga_id
    ON restaurant.order_outbox (type, saga_id, approval_status, outbox_status);

CREATE INDEX restaurant_order_outbox_saga_status
    ON restaurant.order_outbox (type, approval_status);

CREATE MATERIALIZED VIEW restaurant.order_restaurant_m_view AS
SELECT r.id        AS restaurant_id,
       r.name      AS restaurant_name,
       r.active    AS restaurant_active,
       p.id        AS product_id,
       p.name      AS product_name,
       p.price     AS product_price,
       p.available AS product_available
FROM restaurant.restaurants r,
     restaurant.products p,
     restaurant.restaurant_products rp
WHERE r.id = rp.restaurant_id
  AND p.id = rp.product_id;

CREATE FUNCTION restaurant.refresh_order_restaurant_m_view() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    refresh materialized VIEW restaurant.order_restaurant_m_view;
    return null;
END;
$$;

CREATE TRIGGER refresh_order_restaurant_m_view
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON restaurant.restaurant_products
    FOR EACH STATEMENT
EXECUTE PROCEDURE restaurant.refresh_order_restaurant_m_view();
