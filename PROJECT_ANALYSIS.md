# Food Ordering System 项目分析

## 1. 项目概览

这是一个基于 Spring Boot 的食品下单微服务示例项目，核心目标是演示 **DDD 分层、事件驱动微服务、Saga 编排、Transactional Outbox、Kafka/Avro 消息通信** 在订单业务中的组合使用。

业务主流程：

1. Customer Service 创建客户，并向 Kafka 发布客户创建事件。
2. Order Service 消费客户事件，维护本地客户冗余数据。
3. 用户通过 Order Service 创建订单。
4. Order Service 写入订单和 payment outbox 记录。
5. 定时任务扫描 outbox，将支付请求发送到 Kafka。
6. Payment Service 消费支付请求，完成扣款或取消支付，并写入自己的 outbox。
7. Payment Service 定时发布支付响应。
8. Order Service 消费支付响应；支付成功后进入餐厅审批阶段，支付失败则取消订单。
9. Restaurant Service 消费餐厅审批请求，校验餐厅和商品后发布审批结果。
10. Order Service 消费审批结果；审批成功则订单完成，审批失败则触发支付补偿。

## 2. 模块划分

根项目是 Maven 多模块工程，父工程坐标为：

- `groupId`: `com.food.ordering.system`
- `artifactId`: `food-ordering-system`
- `version`: `1.0-SNAPSHOT`
- Java 版本：17
- Spring Boot：2.6.7

### 2.1 根模块

| 模块 | 说明 |
| --- | --- |
| `order-service` | 订单服务，系统的 Saga 协调者，提供下单和查单接口 |
| `payment-service` | 支付服务，处理支付请求和支付补偿 |
| `restaurant-service` | 餐厅服务，处理订单审批 |
| `customer-service` | 客户服务，提供创建客户接口并发布客户事件 |
| `common` | 公共领域模型、异常、Web 异常处理、公共数据访问模型 |
| `infrastructure` | Kafka、Saga、Outbox 等基础设施模块 |
| `infra` | Kubernetes 部署 YAML |

### 2.2 业务服务内部结构

各业务服务大体采用一致的分层结构：

| 子模块 | 职责 |
| --- | --- |
| `*-container` | Spring Boot 启动模块，应用配置、初始化 SQL |
| `*-application` | REST Controller、应用层异常处理 |
| `*-domain/*-domain-core` | 领域实体、值对象、领域服务、领域事件 |
| `*-domain/*-application-service` | 应用服务、命令处理器、端口接口、Saga/Outbox 协调逻辑 |
| `*-dataaccess` | JPA Entity、Repository Adapter、数据库映射 |
| `*-messaging` | Kafka Listener/Publisher、Avro 与领域 DTO 映射 |

### 2.3 基础设施模块

| 模块 | 职责 |
| --- | --- |
| `infrastructure/kafka/kafka-model` | Avro schema 和生成的 Avro Java Model |
| `infrastructure/kafka/kafka-producer` | Kafka Producer 封装、发送回调辅助类 |
| `infrastructure/kafka/kafka-consumer` | Kafka Consumer 配置和统一消费接口 |
| `infrastructure/kafka/kafka-config-data` | Kafka Producer/Consumer/Cluster 配置属性 |
| `infrastructure/saga` | Saga 状态、SagaStep 接口、订单 Saga 常量 |
| `infrastructure/outbox` | Outbox 状态、调度接口、调度配置 |

## 3. 技术选择

| 类型 | 技术 |
| --- | --- |
| 语言 | Java 17 |
| 框架 | Spring Boot 2.6.7 |
| Web | Spring MVC / `spring-boot-starter-web` |
| 数据访问 | Spring Data JPA / Hibernate |
| 数据库 | PostgreSQL |
| 消息队列 | Apache Kafka，Confluent Kafka 镜像 |
| 消息序列化 | Apache Avro + Confluent Schema Registry |
| 分布式事务模式 | Saga 编排 + Transactional Outbox |
| 构建工具 | Maven |
| 辅助库 | Lombok、Mockito、Spring Boot Test |
| 本地中间件编排 | Docker Compose |
| 部署描述 | Kubernetes Deployment / Service YAML |

## 4. 服务与端口

本地 `application.yml` 中配置的服务端口：

| 服务 | 本地端口 | 主要职责 |
| --- | ---: | --- |
| Order Service | `8181` | 创建订单、查询订单、协调 Saga |
| Payment Service | `8182` | 消费支付请求、处理扣款和退款补偿 |
| Restaurant Service | `8183` | 消费餐厅审批请求、返回审批结果 |
| Customer Service | `8184` | 创建客户、发布客户创建事件 |

Kubernetes Service YAML 中暴露端口为 `8081`、`8082`、`8083`、`8084`。

## 5. REST 接口

### 5.1 创建订单

- 服务：Order Service
- 方法：`POST`
- 路径：`/orders`
- Produces：`application/vnd.api.v1+json`
- Controller：`order-service/order-application/.../OrderController.java`

请求体：

```json
{
  "customerId": "uuid",
  "restaurantId": "uuid",
  "price": 100.00,
  "items": [
    {
      "productId": "uuid",
      "quantity": 2,
      "price": 50.00,
      "subTotal": 100.00
    }
  ],
  "address": {
    "street": "string",
    "postalCode": "string",
    "city": "string"
  }
}
```

响应体：

```json
{
  "orderTrackingId": "uuid",
  "orderStatus": "PENDING",
  "message": "Order created successfully"
}
```

订单状态定义在 `common-domain` 中，数据库枚举包含：

- `PENDING`
- `PAID`
- `APPROVED`
- `CANCELLED`
- `CANCELLING`

### 5.2 查询订单

- 服务：Order Service
- 方法：`GET`
- 路径：`/orders/{trackingId}`
- Produces：`application/vnd.api.v1+json`

响应体：

```json
{
  "orderTrackingId": "uuid",
  "orderStatus": "APPROVED",
  "failureMessages": []
}
```

### 5.3 创建客户

- 服务：Customer Service
- 方法：`POST`
- 路径：`/customers`
- Produces：`application/vnd.api.v1+json`
- Controller：`customer-service/customer-application/.../CustomerController.java`

请求体：

```json
{
  "customerId": "uuid",
  "username": "string",
  "firstName": "string",
  "lastName": "string"
}
```

响应体：

```json
{
  "customerId": "uuid",
  "message": "string"
}
```

## 6. Kafka 事件接口

项目使用 Kafka Topic 作为服务间异步接口，消息格式由 Avro schema 定义，Schema Registry 地址本地配置为 `http://localhost:8081`。

### 6.1 Topic 清单

| Topic | 生产者 | 消费者 | 说明 |
| --- | --- | --- | --- |
| `customer` | Customer Service | Order Service | 客户创建事件，用于订单服务维护客户本地副本 |
| `payment-request` | Order Service | Payment Service | 订单发起支付或取消支付请求 |
| `payment-response` | Payment Service | Order Service | 支付完成、失败或取消结果 |
| `restaurant-approval-request` | Order Service | Restaurant Service | 支付成功后的餐厅审批请求 |
| `restaurant-approval-response` | Restaurant Service | Order Service | 餐厅审批通过或拒绝结果 |

Docker Compose 的 `init_kafka.yml` 会创建以上 5 个 Topic，每个 Topic 配置为：

- partitions：3
- replication-factor：3

### 6.2 Consumer Group

| Consumer Group | 使用方 | Topic |
| --- | --- | --- |
| `customer-topic-consumer` | Order Service | `customer` |
| `payment-topic-consumer` | Payment Service / Order Service | `payment-request` / `payment-response` |
| `restaurant-approval-topic-consumer` | Restaurant Service / Order Service | `restaurant-approval-request` / `restaurant-approval-response` |

### 6.3 Avro 消息模型

#### CustomerAvroModel

字段：

- `id`
- `username`
- `firstName`
- `lastName`

#### PaymentRequestAvroModel

字段：

- `id`
- `sagaId`
- `customerId`
- `orderId`
- `price`
- `createdAt`
- `paymentOrderStatus`: `PENDING` / `CANCELLED`

#### PaymentResponseAvroModel

字段：

- `id`
- `sagaId`
- `paymentId`
- `customerId`
- `orderId`
- `price`
- `createdAt`
- `paymentStatus`: `COMPLETED` / `CANCELLED` / `FAILED`
- `failureMessages`

#### RestaurantApprovalRequestAvroModel

字段：

- `id`
- `sagaId`
- `restaurantId`
- `orderId`
- `restaurantOrderStatus`: `PAID`
- `products`: `id`、`quantity`
- `price`
- `createdAt`

#### RestaurantApprovalResponseAvroModel

字段：

- `id`
- `sagaId`
- `restaurantId`
- `orderId`
- `createdAt`
- `orderApprovalStatus`: `APPROVED` / `REJECTED`
- `failureMessages`

## 7. 架构设计

### 7.1 DDD 与端口适配器

项目采用接近 Hexagonal Architecture / Ports and Adapters 的组织方式：

- Controller 和 Kafka Listener 是输入适配器。
- Application Service 是输入端口实现或业务用例协调者。
- Repository、Message Publisher 是输出端口。
- DataAccess 和 Messaging 模块是输出适配器。
- Domain Core 不依赖 Spring 或基础设施，承载领域实体、值对象、领域服务和领域事件。

这种结构让领域规则与基础设施解耦，尤其适合订单、支付、餐厅审批这种跨服务业务流程。

### 7.2 Saga 编排

Order Service 是 Saga 协调者，Saga 状态包括：

- `STARTED`
- `PROCESSING`
- `SUCCEEDED`
- `FAILED`
- `COMPENSATING`
- `COMPENSATED`

订单 Saga 主要分两步：

1. `OrderPaymentSaga`
   - 处理支付响应。
   - 支付成功：订单从 `PENDING` 进入 `PAID`，并创建餐厅审批 outbox。
   - 支付失败：订单进入取消流程。

2. `OrderApprovalSaga`
   - 处理餐厅审批响应。
   - 审批成功：订单进入 `APPROVED`，Saga 成功。
   - 审批失败：订单进入 `CANCELLING`，并写入支付补偿 outbox。

### 7.3 Transactional Outbox

项目使用 outbox 表解决“本地数据库写入成功但消息发送失败”的双写一致性问题。

典型流程：

1. 业务事务中同时写入业务表和 outbox 表。
2. 定时任务扫描 `STARTED` 状态的 outbox 消息。
3. Kafka Publisher 发送消息。
4. 发送成功后将 outbox 状态更新为 `COMPLETED`。
5. 清理任务按策略清理已完成消息。

Outbox 状态：

- `STARTED`
- `COMPLETED`
- `FAILED`

各服务 outbox 表：

| 服务 | Outbox 表 |
| --- | --- |
| Order Service | `"order".payment_outbox` |
| Order Service | `"order".restaurant_approval_outbox` |
| Payment Service | `payment.order_outbox` |
| Restaurant Service | `restaurant.order_outbox` |

定时任务配置：

- `outbox-scheduler-fixed-rate`: `10000`
- `outbox-scheduler-initial-delay`: `10000`
- 清理任务使用 `@Scheduled(cron = "@midnight")`

## 8. 数据库设计

项目使用同一个 PostgreSQL 实例，通过不同 schema 隔离服务数据：

- `order`
- `payment`
- `restaurant`
- `customer`

本地默认连接：

- host：`localhost`
- port：`5432`
- database：`postgres`
- username：`postgres`
- password：`123456`

数据库 SQL 脚本位置：

| 服务 | 建表脚本 | 初始化数据脚本 |
| --- | --- | --- |
| Order Service | `order-service/order-container/src/main/resources/init-schema.sql` | 无 |
| Payment Service | `payment-service/payment-container/src/main/resources/init-schema.sql` | `payment-service/payment-container/src/main/resources/init-data.sql` |
| Restaurant Service | `restaurant-service/restaurant-container/src/main/resources/init-schema.sql` | `restaurant-service/restaurant-container/src/main/resources/init-data.sql` |
| Customer Service | `customer-service/customer-container/src/main/resources/init-schema.sql` | 无 |

各服务 `application.yml` 中都配置了 PostgreSQL JDBC URL，并使用 `currentSchema` 指定当前 schema。配置中 `schema: classpath:init-schema.sql` 目前是注释状态。

### 8.1 Order Schema

SQL 文件：`order-service/order-container/src/main/resources/init-schema.sql`

初始化动作：

- 删除并重建 `"order"` schema。
- 创建 PostgreSQL 扩展 `uuid-ossp`。
- 创建订单、订单明细、订单地址、Outbox、客户副本相关表。
- 创建业务枚举类型：`order_status`、`saga_status`、`outbox_status`。

枚举类型：

| 类型 | 值 |
| --- | --- |
| `order_status` | `PENDING`、`PAID`、`APPROVED`、`CANCELLED`、`CANCELLING` |
| `saga_status` | `STARTED`、`FAILED`、`SUCCEEDED`、`PROCESSING`、`COMPENSATING`、`COMPENSATED` |
| `outbox_status` | `STARTED`、`COMPLETED`、`FAILED` |

核心表：

| 表 | 说明 |
| --- | --- |
| `orders` | 订单主表 |
| `order_items` | 订单明细 |
| `order_address` | 订单地址 |
| `payment_outbox` | 支付请求/补偿请求 outbox |
| `restaurant_approval_outbox` | 餐厅审批请求 outbox |
| `customers` | 订单服务内的客户数据副本 |

主要字段：

| 表 | 字段 |
| --- | --- |
| `orders` | `id`、`customer_id`、`restaurant_id`、`tracking_id`、`price`、`order_status`、`failure_messages` |
| `order_items` | `id`、`order_id`、`product_id`、`price`、`quantity`、`sub_total` |
| `order_address` | `id`、`order_id`、`street`、`postal_code`、`city` |
| `payment_outbox` | `id`、`saga_id`、`created_at`、`processed_at`、`type`、`payload`、`outbox_status`、`saga_status`、`order_status`、`version` |
| `restaurant_approval_outbox` | `id`、`saga_id`、`created_at`、`processed_at`、`type`、`payload`、`outbox_status`、`saga_status`、`order_status`、`version` |
| `customers` | `id`、`username`、`first_name`、`last_name` |

约束和索引：

- `order_items.order_id` 外键关联 `"order".orders.id`，删除订单时级联删除明细。
- `order_address.order_id` 外键关联 `"order".orders.id`，且 `order_id` 唯一。
- `payment_outbox` 上有 `(type, outbox_status, saga_status)` 索引。
- `restaurant_approval_outbox` 上有 `(type, outbox_status, saga_status)` 索引。

### 8.2 Payment Schema

SQL 文件：

- 建表：`payment-service/payment-container/src/main/resources/init-schema.sql`
- 初始化数据：`payment-service/payment-container/src/main/resources/init-data.sql`

初始化动作：

- 删除并重建 `payment` schema。
- 创建 PostgreSQL 扩展 `uuid-ossp`。
- 创建支付、信用额度、信用流水、Outbox 相关表。
- 创建业务枚举类型：`payment_status`、`transaction_type`、`outbox_status`。

枚举类型：

| 类型 | 值 |
| --- | --- |
| `payment_status` | `COMPLETED`、`CANCELLED`、`FAILED` |
| `transaction_type` | `DEBIT`、`CREDIT` |
| `outbox_status` | `STARTED`、`COMPLETED`、`FAILED` |

核心表：

| 表 | 说明 |
| --- | --- |
| `payments` | 支付记录 |
| `credit_entry` | 客户总额度 |
| `credit_history` | 客户额度流水 |
| `order_outbox` | 支付响应 outbox |

主要字段：

| 表 | 字段 |
| --- | --- |
| `payments` | `id`、`customer_id`、`order_id`、`price`、`created_at`、`status` |
| `credit_entry` | `id`、`customer_id`、`total_credit_amount` |
| `credit_history` | `id`、`customer_id`、`amount`、`type` |
| `order_outbox` | `id`、`saga_id`、`created_at`、`processed_at`、`type`、`payload`、`outbox_status`、`payment_status`、`version` |

约束和索引：

- `payments.id`、`credit_entry.id`、`credit_history.id`、`order_outbox.id` 都是主键。
- `order_outbox` 上有 `(type, payment_status)` 索引。
- `order_outbox` 上有唯一索引 `(type, saga_id, payment_status, outbox_status)`，用于减少重复处理。

初始化数据中存在两个客户额度示例：

- 客户 `...fb41` 总额度 `500.00`
- 客户 `...fb43` 总额度 `100.00`

`credit_history` 中还初始化了对应的 `CREDIT` 和 `DEBIT` 流水，用于支付额度校验。

### 8.3 Restaurant Schema

SQL 文件：

- 建表：`restaurant-service/restaurant-container/src/main/resources/init-schema.sql`
- 初始化数据：`restaurant-service/restaurant-container/src/main/resources/init-data.sql`

初始化动作：

- 删除并重建 `restaurant` schema。
- 创建 PostgreSQL 扩展 `uuid-ossp`。
- 创建餐厅、商品、餐厅商品关联、订单审批、Outbox 表。
- 创建订单查询用物化视图 `order_restaurant_m_view`。
- 创建刷新物化视图的函数和 trigger。

枚举类型：

| 类型 | 值 |
| --- | --- |
| `approval_status` | `APPROVED`、`REJECTED` |
| `outbox_status` | `STARTED`、`COMPLETED`、`FAILED` |

核心表：

| 表 / 视图 | 说明 |
| --- | --- |
| `restaurants` | 餐厅 |
| `products` | 商品 |
| `restaurant_products` | 餐厅商品关联 |
| `order_approval` | 订单审批记录 |
| `order_outbox` | 餐厅审批响应 outbox |
| `order_restaurant_m_view` | 给订单校验使用的物化视图 |

主要字段：

| 表 / 视图 | 字段 |
| --- | --- |
| `restaurants` | `id`、`name`、`active` |
| `products` | `id`、`name`、`price`、`available` |
| `restaurant_products` | `id`、`restaurant_id`、`product_id` |
| `order_approval` | `id`、`restaurant_id`、`order_id`、`status` |
| `order_outbox` | `id`、`saga_id`、`created_at`、`processed_at`、`type`、`payload`、`outbox_status`、`approval_status`、`version` |
| `order_restaurant_m_view` | `restaurant_id`、`restaurant_name`、`restaurant_active`、`product_id`、`product_name`、`product_price`、`product_available` |

约束、索引和触发器：

- `restaurant_products.restaurant_id` 外键关联 `restaurant.restaurants.id`。
- `restaurant_products.product_id` 外键关联 `restaurant.products.id`。
- `order_outbox` 上有 `(type, approval_status)` 索引。
- `order_outbox` 上有唯一索引 `(type, saga_id, approval_status, outbox_status)`。
- `restaurant_products` 发生插入、更新、删除或 truncate 后，会触发刷新 `order_restaurant_m_view`。

`init-data.sql` 中餐厅和商品初始化数据目前是注释状态。

### 8.4 Customer Schema

SQL 文件：`customer-service/customer-container/src/main/resources/init-schema.sql`

初始化动作：

- 删除并重建 `customer` schema。
- 创建 PostgreSQL 扩展 `uuid-ossp`。
- 创建客户表。
- 创建订单查询用物化视图 `order_customer_m_view`。
- 创建刷新物化视图的函数和 trigger。

核心表 / 视图：

| 表 / 视图 | 说明 |
| --- | --- |
| `customers` | 客户主表 |
| `order_customer_m_view` | 面向订单查询的客户物化视图 |

主要字段：

| 表 / 视图 | 字段 |
| --- | --- |
| `customers` | `id`、`username`、`first_name`、`last_name` |
| `order_customer_m_view` | `id`、`username`、`first_name`、`last_name` |

触发器：

- `customers` 发生插入、更新、删除或 truncate 后，会触发刷新 `order_customer_m_view`。

## 9. 第三方中间件

### 9.1 PostgreSQL

用于持久化各服务业务数据和 outbox 消息。服务通过 schema 隔离，而不是每个服务一个独立数据库实例。

### 9.2 Kafka Cluster

Docker Compose 定义了 3 个 Kafka Broker：

| Broker | 本地端口 |
| --- | ---: |
| `kafka-broker-1` | `19092` |
| `kafka-broker-2` | `29092` |
| `kafka-broker-3` | `39092` |

应用配置中的 `bootstrap-servers`：

```yaml
localhost:19092, localhost:29092, localhost:39092
```

### 9.3 Zookeeper

Kafka 集群依赖 Zookeeper：

- service：`zookeeper`
- port：`2181`

### 9.4 Schema Registry

用于管理 Avro schema：

- Docker service：`schema-registry`
- 本地端口：`8081`
- 应用配置：`http://localhost:8081`

### 9.5 Kafka Manager

Docker Compose 中包含 Kafka Manager：

- image：`hlebalbau/kafka-manager:stable`
- port：`9000`

## 10. Kafka Docker Compose 部署详解

Kafka 相关部署文件位于 `infrastructure/docker-compose`：

| 文件 | 作用 |
| --- | --- |
| `.env` | 定义 Kafka 版本、Docker 网络名等环境变量 |
| `common.yml` | 定义公共 Docker network |
| `zookeeper.yml` | 定义 Zookeeper 服务 |
| `kafka_cluster.yml` | 定义 3 个 Kafka Broker、Schema Registry、Kafka Manager |
| `init_kafka.yml` | 初始化业务 Topic |

### 10.1 版本

`.env` 中配置：

```env
KAFKA_VERSION=7.0.12
GLOBAL_NETWORK=food-ordering-system
GROUP_ID=com.food.ordering.system
```

实际使用的镜像：

| 组件 | 镜像 |
| --- | --- |
| Kafka Broker | `confluentinc/cp-kafka:7.0.12` |
| Zookeeper | `confluentinc/cp-zookeeper:7.0.12` |
| Schema Registry | `confluentinc/cp-schema-registry:7.0.12` |
| Kafka Manager | `hlebalbau/kafka-manager:stable` |

### 10.2 组件关系

```text
Spring Boot 服务
  -> localhost:19092 / localhost:29092 / localhost:39092
  -> Kafka Broker 1 / 2 / 3
  -> Zookeeper 管理 broker 元数据

Spring Boot 服务
  -> http://localhost:8081
  -> Schema Registry
  -> Kafka 内部 Topic _schemas

Kafka Manager
  -> zookeeper:2181
  -> 查看和管理 Kafka 集群
```

### 10.3 组件作用

| 组件 | 容器内地址 | 宿主机访问 | 作用 |
| --- | --- | --- | --- |
| `zookeeper` | `zookeeper:2181` | `localhost:2181` | 管理 Kafka 集群元数据、broker 注册、controller 选举 |
| `kafka-broker-1` | `kafka-broker-1:9092` | `localhost:19092` | Kafka broker 节点 1 |
| `kafka-broker-2` | `kafka-broker-2:9092` | `localhost:29092` | Kafka broker 节点 2 |
| `kafka-broker-3` | `kafka-broker-3:9092` | `localhost:39092` | Kafka broker 节点 3 |
| `schema-registry` | `schema-registry:8081` | `localhost:8081` | 管理 Avro schema，schema 数据写入 Kafka `_schemas` Topic |
| `kafka-manager` | `kafka-manager:9000` | `localhost:9000` | Kafka Web 管理界面 |

### 10.4 Broker 监听地址

每个 broker 配置了两类 listener：

```yaml
KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka-broker-1:9092,LISTENER_LOCAL://localhost:19092
KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,LISTENER_LOCAL:PLAINTEXT
KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
```

含义：

- `PLAINTEXT://kafka-broker-X:9092`：Docker 网络内部通信使用，包括 broker 间通信、Schema Registry、容器内命令。
- `LISTENER_LOCAL://localhost:X9092`：宿主机上的 Spring Boot 服务连接使用。
- `KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT`：broker 之间使用容器网络地址通信。

应用侧 Kafka 配置应使用宿主机端口：

```yaml
bootstrap-servers: localhost:19092, localhost:29092, localhost:39092
schema-registry-url: http://localhost:8081
```

### 10.5 数据持久化

当前 Kafka compose 使用 bind mount，数据落在项目目录：

| 组件 | 容器内目录 | 宿主机目录 |
| --- | --- | --- |
| Zookeeper data | `/var/lib/zookeeper/data` | `infrastructure/docker-compose/volumes/zookeeper/data` |
| Zookeeper log | `/var/lib/zookeeper/log` | `infrastructure/docker-compose/volumes/zookeeper/transactions` |
| Broker 1 | `/var/lib/kafka/data` | `infrastructure/docker-compose/volumes/kafka/broker-1` |
| Broker 2 | `/var/lib/kafka/data` | `infrastructure/docker-compose/volumes/kafka/broker-2` |
| Broker 3 | `/var/lib/kafka/data` | `infrastructure/docker-compose/volumes/kafka/broker-3` |

这和 PostgreSQL 的 Docker named volume 不同。Kafka 数据目录是直接映射到当前项目下的 `volumes` 目录，因此删除容器后数据仍在；删除这些目录后 Kafka/Zookeeper 数据会丢失。

### 10.6 Topic 初始化

`init_kafka.yml` 使用 `confluentinc/cp-kafka:7.0.12` 镜像执行 `kafka-topics` 命令。

初始化脚本会先删除再创建业务 Topic：

| Topic | 分区数 | 副本数 | 业务含义 |
| --- | ---: | ---: | --- |
| `customer` | 3 | 3 | Customer Service 发布客户创建事件，Order Service 消费 |
| `payment-request` | 3 | 3 | Order Service 发起支付/取消支付请求，Payment Service 消费 |
| `payment-response` | 3 | 3 | Payment Service 发布支付结果，Order Service 消费 |
| `restaurant-approval-request` | 3 | 3 | Order Service 发起餐厅审批请求，Restaurant Service 消费 |
| `restaurant-approval-response` | 3 | 3 | Restaurant Service 发布审批结果，Order Service 消费 |

集群中还会出现 Kafka 内部 Topic：

| Topic | 来源 | 说明 |
| --- | --- | --- |
| `__consumer_offsets` | Kafka 自动创建 | 保存 Consumer Group offset |
| `_schemas` | Schema Registry 自动创建 | 保存 Avro schema |

当前验证到的业务 Topic 示例：

```text
Topic: customer
PartitionCount: 3
ReplicationFactor: 3
ISR: 1,2,3

Topic: payment-request
PartitionCount: 3
ReplicationFactor: 3
ISR: 1,2,3
```

ISR 包含 `1,2,3` 说明三个 broker 的副本均处于同步状态。

### 10.7 启动和验证命令

启动 Kafka 集群：

```bash
cd infrastructure/docker-compose
docker compose -f common.yml -f zookeeper.yml -f kafka_cluster.yml up -d
```

初始化 Topic：

```bash
docker compose -f common.yml -f init_kafka.yml up init-kafka
```

查看容器状态：

```bash
docker compose -f common.yml -f zookeeper.yml -f kafka_cluster.yml ps
```

查看 Topic：

```bash
docker exec -it docker-compose-kafka-broker-1-1 \
  kafka-topics --bootstrap-server kafka-broker-1:9092 --list
```

查看 Topic 详情：

```bash
docker exec -it docker-compose-kafka-broker-1-1 \
  kafka-topics --bootstrap-server kafka-broker-1:9092 --describe --topic customer
```

访问 Schema Registry：

```bash
curl http://localhost:8081/subjects
```

访问 Kafka Manager：

```text
http://localhost:9000
```

停止集群：

```bash
docker compose -f common.yml -f zookeeper.yml -f kafka_cluster.yml down
```

注意：`down` 会删除容器和网络，但不会删除项目目录下的 Kafka/Zookeeper 数据。若要清空 Kafka 数据，需要删除 `infrastructure/docker-compose/volumes/kafka` 和 `infrastructure/docker-compose/volumes/zookeeper`。

### 10.8 业务消息流

```text
Customer Service
  -> customer
  -> Order Service

Order Service
  -> payment-request
  -> Payment Service

Payment Service
  -> payment-response
  -> Order Service

Order Service
  -> restaurant-approval-request
  -> Restaurant Service

Restaurant Service
  -> restaurant-approval-response
  -> Order Service
```

项目的消息体使用 Avro 序列化：

- Producer 使用 `io.confluent.kafka.serializers.KafkaAvroSerializer`
- Consumer 使用 `io.confluent.kafka.serializers.KafkaAvroDeserializer`
- Schema Registry 地址为 `http://localhost:8081`

## 11. 部署配置

### 11.1 Docker Compose

位置：`infrastructure/docker-compose`

包含：

- `zookeeper.yml`
- `kafka_cluster.yml`
- `init_kafka.yml`

用途：

- 启动 Zookeeper。
- 启动 3 节点 Kafka 集群。
- 启动 Schema Registry。
- 启动 Kafka Manager。
- 初始化业务 Topic。

### 11.2 Kubernetes

位置：`infra`

包含：

- `application-deployment.yaml`
- `postgres-deployment.yaml`

定义了：

- 4 个业务服务 Deployment。
- 4 个业务服务 LoadBalancer Service。
- PostgreSQL Deployment 和 Service。

注意：`application-deployment.yaml` 中 payment、restaurant、customer 的 `SPRING_DATASOURCE_URL` 当前都指向了 `currentSchema=order`，这看起来不像预期配置；按本地配置应分别指向 `payment`、`restaurant`、`customer` schema。

## 12. 关键业务流程

### 12.1 客户创建与同步

```text
POST /customers
  -> Customer Service 保存客户
  -> 发布 CustomerAvroModel 到 customer Topic
  -> Order Service 消费 customer Topic
  -> 写入 order.customers 本地副本
```

### 12.2 正常下单流程

```text
POST /orders
  -> Order Service 创建 PENDING 订单
  -> 写入 order.payment_outbox
  -> Outbox Scheduler 发布 payment-request
  -> Payment Service 消费 payment-request
  -> 扣减客户额度并写入 payment.order_outbox
  -> Payment Service 发布 payment-response COMPLETED
  -> Order Service 消费 payment-response
  -> 订单变更为 PAID
  -> 写入 order.restaurant_approval_outbox
  -> Order Service 发布 restaurant-approval-request
  -> Restaurant Service 审批订单
  -> 发布 restaurant-approval-response APPROVED
  -> Order Service 消费审批结果
  -> 订单变更为 APPROVED
```

### 12.3 支付失败流程

```text
payment-response FAILED
  -> Order Service 消费支付失败事件
  -> 订单取消
  -> Saga 进入失败/补偿结束状态
```

### 12.4 餐厅拒绝后的补偿流程

```text
restaurant-approval-response REJECTED
  -> Order Service 将订单置为 CANCELLING
  -> 写入 payment_outbox，生成取消支付请求
  -> Payment Service 消费 payment-request CANCELLED
  -> 回滚/释放支付
  -> 发布 payment-response CANCELLED
  -> Order Service 消费取消结果
  -> 订单变更为 CANCELLED
```

## 13. 代码阅读中发现的注意点

以下是静态阅读时发现的潜在问题，建议后续单独验证：

1. `OrderPaymentSaga` 和 `OrderApprovalSaga` 中多处 `Optional` 判断逻辑疑似反了。
   - 代码当前在 `isPresent()` 时直接返回或抛错，随后又调用 `.get()`。
   - 这可能导致正常存在数据时被误判为“已处理”，不存在数据时抛出 `NoSuchElementException`。

2. `OrderPaymentSaga.findOrder` 中也存在类似问题。
   - 当前逻辑在 `orderResponse.isPresent()` 时抛出 `OrderNotFoundException`，随后返回 `orderResponse.get()`。

3. REST 入参 DTO 使用了 `javax.validation` 注解，但 Controller 方法参数没有 `@Valid`。
   - 当前 `@NotNull` 等约束可能不会在请求入口自动生效。

4. `OrderAddress` 中字符串长度使用了 `@Max`。
   - `@Max` 适用于数字类型，字符串长度通常应使用 `@Size(max = ...)`。

5. K8s 配置中的 schema 指向疑似错误。
   - payment、restaurant、customer 服务的 datasource URL 都配置成了 `currentSchema=order`。

6. 餐厅初始化数据目前全部注释。
   - 如果没有外部数据导入，餐厅审批可能因为找不到餐厅或商品而失败。

## 14. 建议的后续完善

1. 为 Saga 正向流程和补偿流程补充集成测试。
2. 修正 `Optional` 判断逻辑并增加回归测试。
3. 在 REST Controller 的请求体参数上添加 `@Valid`。
4. 将字符串字段校验从 `@Max` 调整为 `@Size`。
5. 梳理 K8s 环境变量命名和 datasource schema。
6. 为本地启动补充统一 README，包括 Docker Compose 启动顺序、Topic 初始化和测试请求样例。
7. 为 Avro 消息增加版本演进说明，明确兼容策略。
