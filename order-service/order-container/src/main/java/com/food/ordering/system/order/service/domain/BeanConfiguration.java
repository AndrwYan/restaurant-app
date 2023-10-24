package com.food.ordering.system.order.service.domain;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class BeanConfiguration {

    /**
     * @Description: 初始化核心域
     * @Author:
     * @Date:
     * @return: com.food.ordering.system.order.service.domain.OrderDomainService
     **/
    @Bean
    public OrderDomainService orderDomainService() {

        return new OrderDomainServiceImpl();
    }
}
