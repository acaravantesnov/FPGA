--=================================================================================================
-- Title       : FIFO
-- File        : fifo_rtl.vhd
-- Description : Custom 1-bit input FIFO. It is written 1-bit at a time, and acts as a shift
--               register from left to right. Once it is full, it generates a pulse at fifo_full,
--               indicating the FSM that it should be registered at the output of the PUF. It
--               cannot be read bit by bit by pulling from the right of the FIFO as in a
--               traditional FIFO.
-- Generics    : g_width            -> Width of the FIFO, width of the output response of the PUF,
--                                     and width at which it triggers the fifo_full flag.
--               g_reset_polarity   -> Active high ('1') or active low ('0') rest for both reset_n
--                                     and aux_reset_n.
-- Author      : Alberto Caravantes Arranz
-- Date        : 06/04/2025
-- Version     : 1.0
--=================================================================================================

-- Revision History:
-- Version 1.0 - Initial version

library ieee;
use ieee.std_logic_1164.all;

entity fifo is
    generic(
        g_width         : natural range 2 to 16 := 8;
        g_reset_polarity: std_logic := '0'
    );
    port(
        clk         : in std_logic;
        aux_reset_n : in std_logic;
        reset_n     : in std_logic;
        input_value : in std_logic;
        output_value: out std_logic_vector(g_width - 1 downto 0);
        fifo_full   : out std_logic
    );
end entity fifo;

architecture rtl of fifo is

    signal fifo_i: std_logic_vector(g_width - 1 downto 0);
    signal n_shifts_i: natural;

begin

    process(reset_n, clk)
    begin
        if ((reset_n = g_reset_polarity) or (aux_reset_n = g_reset_polarity)) then
            fifo_i <= (others => '0');
            n_shifts_i <= 0;
        elsif (rising_edge(clk)) and (n_shifts_i < g_width) then
            n_shifts_i <= n_shifts_i + 1;
            fifo_i(g_width - 1) <= input_value;
            for i in 2 to g_width loop
                fifo_i(g_width - i) <= fifo_i(g_width - (i - 1));
            end loop;
        end if;
    end process;

    output_value <= fifo_i;
    fifo_full <= '1' when n_shifts_i >= g_width else '0';

end architecture rtl;
