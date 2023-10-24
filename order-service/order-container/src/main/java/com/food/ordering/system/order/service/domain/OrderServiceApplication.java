package com.food.ordering.system.order.service.domain;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.scheduling.annotation.EnableScheduling;

@EnableJpaRepositories(basePackages = { "com.food.ordering.system.order.service.dataaccess", "com.food.ordering.system.dataaccess" })
@EntityScan(basePackages = { "com.food.ordering.system.order.service.dataaccess", "  com.food.ordering.system.dataaccess"})
@EnableScheduling
@SpringBootApplication(scanBasePackages = "com.food.ordering.system")
public class OrderServiceApplication {

    public static void main(String[] args) {
      SpringApplication.run(OrderServiceApplication.class, args);
    }

}
