package com.food.ordering.system.customer.service.domain.ports.output.repository;

import com.food.ordering.system.customer.service.domain.entity.Customer;

//?为什么接口写在domain层？依赖反转靠接口
public interface CustomerRepository {

    Customer createCustomer(Customer customer);
}
