package com.food.ordering.system.saga;

/**
 * @Description: saga的状态分别是 启动，失败，成功，正在处理，正在补偿，补偿完了, order服务作为协调者
 * @Author: yfk
 **/
public enum SagaStatus {
    STARTED, FAILED, SUCCEEDED, PROCESSING, COMPENSATING, COMPENSATED
}
