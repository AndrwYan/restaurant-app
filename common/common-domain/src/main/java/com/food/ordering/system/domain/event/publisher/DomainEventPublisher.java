package com.food.ordering.system.domain.event.publisher;

import com.food.ordering.system.domain.event.DomainEvent;

/**
 * @Description: 定义事件接口
 **/
public interface DomainEventPublisher<T extends DomainEvent> {

    void publish(T domainEvent);

}
