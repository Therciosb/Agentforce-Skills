import { createElement } from 'lwc';
import SkillBuilder from 'c/skillBuilder';
import generateSkill from '@salesforce/apex/Agent_Skill_Builder.generateSkill';

jest.mock(
    '@salesforce/apex/Agent_Skill_Builder.generateSkill',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Flush the microtask + promise chain used inside async handlers.
async function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    await new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-skill-builder', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function build() {
        const el = createElement('c-skill-builder', { is: SkillBuilder });
        document.body.appendChild(el);
        return el;
    }

    it('renders the generate button disabled while intent is empty', () => {
        const el = build();
        const btn = el.shadowRoot.querySelector('lightning-button');
        expect(btn).not.toBeNull();
        expect(btn.disabled).toBe(true);
    });

    it('enables generate once an intent is entered and invokes Apex on click', async () => {
        generateSkill.mockResolvedValue({
            success: true,
            recordId: 'a00000000000001',
            name: 'skill-x'
        });
        const el = build();

        const ta = el.shadowRoot.querySelector('lightning-textarea');
        ta.value = 'do a thing';
        ta.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const btn = el.shadowRoot.querySelector('lightning-button');
        expect(btn.disabled).toBe(false);

        btn.click();
        await flushPromises();

        expect(generateSkill).toHaveBeenCalledTimes(1);
        expect(generateSkill.mock.calls[0][0]).toEqual(
            expect.objectContaining({
                intent: 'do a thing',
                skillType: 'Skill'
            })
        );
    });

    it('fires a success toast when Apex reports success', async () => {
        generateSkill.mockResolvedValue({
            success: true,
            recordId: 'a00000000000001',
            name: 'skill-x'
        });
        const el = build();
        const toastHandler = jest.fn();
        el.addEventListener('lightning__showtoast', toastHandler);

        const ta = el.shadowRoot.querySelector('lightning-textarea');
        ta.value = 'do a thing';
        ta.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('success');
    });

    it('fires an error toast when Apex rejects', async () => {
        generateSkill.mockRejectedValue({ body: { message: 'nope' } });
        const el = build();
        const toastHandler = jest.fn();
        el.addEventListener('lightning__showtoast', toastHandler);

        const ta = el.shadowRoot.querySelector('lightning-textarea');
        ta.value = 'do a thing';
        ta.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(generateSkill).toHaveBeenCalled();
        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('error');
    });
});
