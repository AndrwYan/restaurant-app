package com.food.ordering.system.order.service.domain.ports.input.message.listener.payment;

import com.food.ordering.system.order.service.domain.dto.message.PaymentResponse;

public interface PaymentResponseMessageListener {

    //订单完成
    void paymentCompleted(PaymentResponse paymentResponse);

    //订单取消
    void paymentCancelled(PaymentResponse paymentResponse);
}
