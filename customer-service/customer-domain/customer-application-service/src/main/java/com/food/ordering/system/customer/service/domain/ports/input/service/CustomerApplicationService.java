package com.food.ordering.system.customer.service.domain.ports.input.service;

import com.food.ordering.system.customer.service.domain.create.CreateCustomerCommand;
import com.food.ordering.system.customer.service.domain.create.CreateCustomerResponse;
import javax.validation.Valid;

//这里对应的是六边形架构(也叫端口适配器)的入口
public interface CustomerApplicationService {

    CreateCustomerResponse createCustomer(
            @Valid CreateCustomerCommand createCustomerCommand);

}
