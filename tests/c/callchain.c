/* Exercise repeated nested calls and returns. */
static int leaf(int x)  { return x + 1; }
static int mid(int x)   { return leaf(x) + leaf(x + 1); }
static int outer(int x) { return mid(x) + mid(x + 2); }

int main(void) {
    int acc = 0;
    for (int i = 0; i < 50; i++) {
        acc += outer(i);
    }
    /* closed form: outer(i) = 4i + 10  -> sum over i=0..49 = 4*1225 + 500 */
    return (acc == (4 * 1225 + 500)) ? 0 : 1;
}
