package com.food.ordering.system.saga;

//Saga设计模式
public interface SagaStep<T> {

    void process(T data);

    void rollback(T data);

}
