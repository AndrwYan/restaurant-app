package com.food.ordering.system.outbox;

//1.事务性发件箱(解决双写问题)
public interface OutboxScheduler {

    void processOutboxMessage();

}
