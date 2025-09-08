// ������ �׽�Ʈ��ġ - �⺻ ���۸� Ȯ��
module tb_cnn_system_simple;

    logic clk, rst_n;
    logic spi_slave_sclk, spi_slave_mosi, spi_slave_miso, spi_slave_ss;
    logic spi_master_sclk, spi_master_mosi, spi_master_miso, spi_master_ss;
    logic [3:0] status_led;

    // DUT �ν��Ͻ�
    IP_CNN_System_Fast_Fixed dut (
        .clk(clk),
        .rst_n(rst_n),
        .spi_slave_sclk(spi_slave_sclk),
        .spi_slave_mosi(spi_slave_mosi),
        .spi_slave_miso(spi_slave_miso),
        .spi_slave_ss(spi_slave_ss),
        .spi_master_sclk(spi_master_sclk),
        .spi_master_mosi(spi_master_mosi),
        .spi_master_miso(spi_master_miso),
        .spi_master_ss(spi_master_ss),
        .status_led(status_led)
    );

    // Ŭ�� ���� (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // SPI Slave Ŭ�� ���� (1MHz)
    initial begin
        spi_slave_sclk = 0;
        forever #500 spi_slave_sclk = ~spi_slave_sclk;
    end

    // �׽�Ʈ �ó�����
    initial begin
        // �ʱ�ȭ
        rst_n = 0;
        spi_slave_mosi = 0;
        spi_slave_ss = 1;
        spi_master_miso = 0;
        
        // ���� ����
        #100;
        rst_n = 1;
        
        $display("=== CNN �ý��� �׽�Ʈ ���� ===");
        
        // �⺻ ���� Ȯ��
        #100;
        if (status_led == 4'b0001) begin
            $display("? IDLE ���� Ȯ�ε�");
        end else begin
            $display("? IDLE ���� ����: %b", status_led);
        end
        
        // ������ SPI ���� �ùķ��̼�
        spi_slave_ss = 0;  // SPI ����
        #50;
        
        // �� ����Ʈ ���� (�����δ� 1024����Ʈ �ʿ�)
        for (int i = 0; i < 10; i++) begin
            send_spi_byte(8'hAA + i);
        end
        
        spi_slave_ss = 1;  // SPI ����
        
        // ���� ��ȭ ����
        #1000;
        $display("���� LED: %b", status_led);
        
        // �׽�Ʈ �Ϸ�
        #5000;
        $display("=== �׽�Ʈ �Ϸ� ===");
        $finish;
    end

    // SPI ����Ʈ ���� �½�ũ
    task send_spi_byte(input [7:0] data);
        for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
            @(negedge spi_slave_sclk);
            spi_slave_mosi = data[bit_idx];
            @(posedge spi_slave_sclk);
        end
    endtask

    // ���� ����͸�
    always @(posedge clk) begin
        if (status_led != 4'b0001) begin
            $display("�ð� %t: ���� ���� - LED: %b", $time, status_led);
        end
    end

endmodule